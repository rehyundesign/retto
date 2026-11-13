// 레토를 그리고 마우스를 받는 뷰.

import AppKit
import CoreText
import Foundation

final class RettoView: NSView {
    /// 지금 그리는 아틀라스. 스킨을 고르면 앱이 갈아 끼운다.
    var spriteSheet: NSImage {
        didSet { frameIndex = 0; completedCycles = 0; restartAnimation(); needsDisplay = true }
    }
    /// 아틀라스만으로는 표현하기 어려운 스킨 전용 효과를 고른다.
    var skin: PetSkin {
        didSet {
            if oldValue == .classic && oldValue != skin { ClassicGrown.removeCachedImages() }

            if oldValue != skin {
                switch oldValue {
                case .angelWings: AngelSkin.cache.removeAllObjects(); AngelInteractions.cache.removeAllObjects()
                case .hachupingping: HachupingSkin.purge()
                case .jeanne: JeanneSkin.removeCachedImages()
                case .hana: HanaFrameCache.removeCachedImages()
                case .pichiPitch: PichiSkin.removeCachedImages()
                case .chocolatHeart: ChocolatHeart.removeCachedImages()
                case .amuRan: AmuRanFrames.removeCachedImages()
                default: break
                }
            }
            if skin == .angelWings { spriteRestState=nil }
            if skin == .hachupingping { spriteRestState=nil; _ = hachupingPolicy.select(state,session:payload?.id ?? ""); hachupingLastKey="" }
            if skin == .chocolatHeart { chocolatEpoch = ProcessInfo.processInfo.systemUptime }; clearGaze(); frameIndex = 0; completedCycles = 0; restartAnimation(); restartChristmasEffects(); needsDisplay = true }
    }
    private var spriteLayout: SpriteSheetLayout {
        SpriteSheetLayout.forImage(size: spriteSheet.size) ?? .retto
    }
    /// 변신 효과는 캐릭터 아틀라스와 같은 칸·행을 쓰는 별도 투명 레이어다.
    /// 뒤 레이어 → 레토 → 앞 레이어 순서로 그려서 마법진은 몸 뒤에, 리본 끝은 앞에 남긴다.
    private let onOpenClaude: (StatePayload?, Bool) -> Void
    private let onOpenAttention: (NSPoint) -> Void
    private var payload: StatePayload?
    private var state: PetState = .idle
    private var chocolatPreviewTime: TimeInterval?
    func setChocolatTimeForPreview(_ time: TimeInterval, drag: DragRun? = nil) { chocolatPreviewTime = time; dragRun = drag; needsDisplay = true }
    private var chocolatEpoch = ProcessInfo.processInfo.systemUptime
    private var amuChoice = AmuApproved.Choice()
    func setAmuChoiceForPreview(working:String?,completion:String?) { amuChoice.preview(working:working,completion:completion) }
    private var angelEpoch = ProcessInfo.processInfo.systemUptime
    private var angelPreviewTime:Double?
    private var angelIdleChoice=AngelInteractions.IdleChoice()
    private var angelLastMouseLocation:NSPoint?
    private var angelLastDisplaySample: String?
    func setAngelIdleVariantForPreview(_ value:Int,time:Double){angelPreviewTime=time;angelIdleChoice.force(value,cycle:Int(floor(time/3.2)));needsDisplay=true}
    func setAngelTimeForPreview(_ time:Double){angelPreviewTime=time;needsDisplay=true}
    private var amuRanPoseEpoch = ProcessInfo.processInfo.systemUptime
    private let amuRanEffectEpoch = ProcessInfo.processInfo.systemUptime
    private var amuRanPreviewTime: TimeInterval?
    private var amuRanSpriteOnlyPreview = false
    func setAmuRanTimeForPreview(_ time: TimeInterval) { amuRanPreviewTime = time; needsDisplay = true }
    func setAmuRanSpriteOnlyForPreview() { amuRanSpriteOnlyPreview = true }
    func refreshAmuApprovedVariant() { clearGaze(); frameIndex=0; completedCycles=0; restartAnimation(); needsDisplay=true }
    private var classicGrownEpoch = ProcessInfo.processInfo.systemUptime
    private var hachupingPolicy = HachupingSkin.Policy()
    private var hachupingEpoch = ProcessInfo.processInfo.systemUptime
    private var hachupingEffectsEpoch = ProcessInfo.processInfo.systemUptime
    private var hachupingLastKey = ""
    private var hachupingPreviewTime: Double?
    private var hachupingPreviewWorking: String?
    private var hachupingKey: String { HachupingSkin.key(state:visibleState,drag:dragRun,working:hachupingPreviewWorking ?? hachupingPolicy.workingKey) }
    func setHachupingPreview(time:Double,working:String?,gaze:Int?,held:Bool) {
        hachupingPreviewTime=time;hachupingPreviewWorking=working;lookDirection=gaze
        frameIndex=held ? 0:HachupingSkin.position(hachupingKey,time:time).frame;needsDisplay=true
    }
    private var howlEpoch = ProcessInfo.processInfo.systemUptime
    private var howlPreviewTime: Double?
    private var howlCookingB = false
    private var howlLastRow = -1
    func setHowlVariantForPreview(_ b: Bool) { howlCookingB = b }
    func setHowlTimeForPreview(_ t: Double) {
        howlPreviewTime = t
        if let a = currentAnimation { frameIndex = HowlSkin.position(row:a.row,time:t).frame }
        needsDisplay = true
    }
    private var frameIndex = 0
    private var completedCycles = 0
    private var animationTimer: Timer?
    private var jeanneEpoch = ProcessInfo.processInfo.systemUptime
    private var jeannePreviewTime: Double?
    func setJeanneTimeForPreview(_ time: Double) {
        jeannePreviewTime = time
        if let a = currentAnimation { frameIndex = JeanneSkin.position(row: a.row, time: time).frame }
        needsDisplay = true
    }
    private var pichiEpoch = ProcessInfo.processInfo.systemUptime
    private var pichiPreviewTime: Double?
    func setPichiTimeForPreview(_ time: Double) {
        pichiPreviewTime = time
        if let a = currentAnimation { frameIndex = PichiSkin.position(row: a.row, time: time).frame }
        needsDisplay = true
    }
    private var hanaAnimationStart = ProcessInfo.processInfo.systemUptime
    private let hanaEffects = HanaEffectLayers()
    private var christmasEffectsTimer: Timer?
    private var christmasEffectsStart = ProcessInfo.processInfo.systemUptime
    private var christmasPreviewTime: TimeInterval?
    private var christmasEffectState: String?
    private var trackingAreaRef: NSTrackingArea?
    private var lookDirection: Int?
    /// 시선 행은 방향별 정지 그림 한 장이다. 커서가 멈춘 뒤에도 계속 쓰면 펫까지 멈춘 것처럼 보인다.
    private var gazeResetTimer: Timer?
    private var gazeTransitionTimer: Timer?
    private var gazeTargetDirection: Int?
    private var hanaLastMouseLocation: NSPoint?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var pressedTarget: PetClickTarget?
    private var didDrag = false
    /// 끌고 가는 동안 달리는 방향. 끌지 않으면 nil.
    private var dragRun: DragRun?
    /// 방향을 마지막으로 판단한 마우스 x. 미세한 떨림으로 좌우가 튀지 않게 한다.
    private var lastDragX: CGFloat?
    private var isRibbonHovering = false
    private var sessionCount = 0
    private var attentionCount = 0
    private var inputCount = 0
    private var connectionStatus: String?
    private var isPinned = false
    /// 배지가 대표하는 상태. 다른 세션에 고정해 둔 동안에도 배지 색은 기다리는 쪽을 따른다.
    private var attentionState: PetState?
    private var attentionSource: String?

    /// 클릭 한 번에 한 바퀴만 돌고 원래 상태로 돌아가는 반응 동작. 코덱스의 transientState 와 같은 자리.
    private var transientState: PetState?
    /// 손 흔들기처럼 정해진 횟수만 도는 동작이 끝난 뒤 앉는 자리. 그림만 바뀌고 상태는 그대로다.
    /// 답변이 끝난 세션은 내가 볼 때까지 "완료"로 남아야 하므로 상태를 쉬는 중으로 바꾸지 않는다.
    private var spriteRestState: PetState?
    /// 말풍선에 마우스를 잠깐 올려두면 마지막 답을 읽을 수 있게 아래로 펼친다.
    private(set) var isRibbonExpanded = false
    private var ribbonExpandTimer: Timer?
    var onExpansionChanged: ((Bool) -> Void)?

    /// 코덱스·동물의 숲처럼 멘트가 한 글자씩 찍히게 한다. 새 멘트가 올 때마다 처음부터 다시 찍는다.
    /// 앱이 트랜스크립트에서 직접 읽어 넘겨 주는 문장. 훅보다 빠르다.
    private var liveMessage: String?
    /// 같은 이유로 이름도 직접 읽는다. 훅은 도구 호출 때만 도니, 쉬는 세션 이름을 바꾸면 안 따라왔다.
    private var liveTitle: String?
    private var typingSource = ""
    private var typedCount = 0
    private var typeTimer: Timer?

    private var isBadgeHovering = false
    private var isBadgePressed = false
    /// 마지막으로 그린 배지 자리. 이름표 폭이 글자에 따라 달라지므로 그릴 때 정해 기억해 둔다.
    private var badgeFrame: NSRect = .zero
    private var badgeVisualScale: CGFloat = 1
    private var badgeAppearProgress: CGFloat = 1
    private var badgeAnimator: Timer?

    var petScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var chatScale: CGFloat? {
        didSet { needsDisplay = true }
    }
    var chatFontSize: ChatFontSize = .medium {
        didSet { needsDisplay = true }
    }

    private var layout: PetLayout {
        petLayout(scale: petScale, width: bounds.width, expanded: isRibbonExpanded, chatScale: chatScale, fontSize: chatFontSize)
    }

    /// 지금 화면에 그려야 하는 상태. 반응 → 앉은 자리 → 실제 상태 순으로 이긴다.
    /// 스프라이트만 이 값을 따르고, 말풍선·이름표·우선순위는 언제나 실제 상태(`state`)를 쓴다.
    private var visibleState: PetState {
        if skin == .classic, ClassicGrown.available, sleepPose, transientState == nil { return .sleeping }
        return transientState ?? spriteRestState ?? (sleepPose ? .sleeping : state)
    }

    /// 말풍선·이름표에 쓸 글꼴. 메뉴에서 고른 값을 앱이 넣어 준다.
    var typeface: PetTypeface = .handwriting {
        didSet {
            guard typeface != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 그림만 잠든 상태. 말풍선·이름표·색은 실제 상태를 그대로 쓴다.
    private var sleepPose = false {
        didSet {
            guard sleepPose != oldValue else { return }
            if skin == .hana { clearGaze() }
            frameIndex = 0
            restartAnimation()
            needsDisplay = true
        }
    }

    init(
        frame frameRect: NSRect,
        spriteSheet: NSImage,
        skin: PetSkin = .classic,
        onOpenClaude: @escaping (StatePayload?, Bool) -> Void,
        onOpenAttention: @escaping (NSPoint) -> Void
    ) {
        self.spriteSheet = spriteSheet
        self.skin = skin
        self.onOpenClaude = onOpenClaude
        self.onOpenAttention = onOpenAttention
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Claude Code와 Codex 상태를 보여주는 " + Retto.character + " " + Retto.koreanName)
        restartAnimation()
        restartChristmasEffects()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        animationTimer?.invalidate()
        christmasEffectsTimer?.invalidate()
        gazeResetTimer?.invalidate()
        gazeTransitionTimer?.invalidate()
        badgeAnimator?.invalidate()
        ribbonExpandTimer?.invalidate()
        typeTimer?.invalidate()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    private struct ApplyInputs: Equatable {
        let payload: StatePayload
        let state: PetState?
        let liveMessage: String?
        let liveTitle: String?
        let sleepPose: Bool
        let sessionCount: Int
        let attentionCount: Int
        let attentionState: PetState?
        let attentionSource: String?
        let inputCount: Int
        let connectionStatus: String?
        let isPinned: Bool
    }
    /// 폴링은 0.25초마다 같은 값을 다시 넘긴다. 표시 상태는 여기서만 바뀌므로, 같은 값이면 다시 그리지 않는다.
    private var lastApplyInputs: ApplyInputs?

    func apply(_ newPayload: StatePayload, state incoming: PetState? = nil, liveMessage: String? = nil, liveTitle: String? = nil, sleepPose: Bool = false, sessionCount: Int, attentionCount: Int, attentionState: PetState? = nil, attentionSource: String? = nil, inputCount: Int = 0, connectionStatus: String? = nil, isPinned: Bool) {
        let inputs = ApplyInputs(
            payload: newPayload, state: incoming, liveMessage: liveMessage, liveTitle: liveTitle, sleepPose: sleepPose,
            sessionCount: sessionCount, attentionCount: attentionCount, attentionState: attentionState,
            attentionSource: attentionSource, inputCount: inputCount, connectionStatus: connectionStatus, isPinned: isPinned
        )
        guard inputs != lastApplyInputs else { return }
        lastApplyInputs = inputs
        self.liveMessage = liveMessage
        self.liveTitle = liveTitle
        let hachupingSleepChanged = skin == .hachupingping && self.sleepPose != sleepPose
        self.sleepPose = sleepPose
        payload = newPayload
        self.sessionCount = sessionCount
        let hadBadge = self.attentionCount > 0
        self.attentionCount = attentionCount
        self.attentionState = attentionState
        self.attentionSource = attentionSource
        self.inputCount = inputCount
        self.connectionStatus = connectionStatus
        if !hadBadge && attentionCount > 0 {
            badgeAppearProgress = 0
            startBadgeAnimator()
        }
        if attentionCount == 0 {
            isBadgeHovering = false
            isBadgePressed = false
        }
        self.isPinned = isPinned
        let requestedState = incoming ?? newPayload.petState
        let nextState: PetState = skin == .hachupingping && requestedState == .review ? .running:requestedState
        let previousAmuEpoch=amuRanPoseEpoch
        let sameAmuWork=skin == .amuRan && AmuApproved.Choice.group(state)=="work" && AmuApproved.Choice.group(nextState)=="work"
        let amuChanged=skin == .amuRan && amuChoice.enter(nextState,session:newPayload.id,turn:newPayload.turnId ?? "")
        if skin == .hachupingping {
            let changed = hachupingPolicy.select(nextState,session:newPayload.id)
            if changed { frameIndex=0;completedCycles=0;hachupingLastKey="";restartAnimation() }
        }
        if nextState != state {
            state = nextState
            spriteRestState = nil
            frameIndex = 0
            completedCycles = 0
            clearGaze()
            restartAnimation()
        }
        if skin == .amuRan {
            if amuChanged { spriteRestState=nil;frameIndex=0;completedCycles=0;restartAnimation() }
            else if sameAmuWork { amuRanPoseEpoch=previousAmuEpoch }
        }
        if hachupingSleepChanged { clearGaze();frameIndex=0;completedCycles=0;restartAnimation() }
        restartTypingIfNeeded()
        needsDisplay = true
        updateAccessibility()
    }

    /// 배지의 등장 팝과 hover/press 크기 변화를 60fps 로 굴린다. 다 자리 잡으면 스스로 멈춘다.
    private func startBadgeAnimator() {
        guard badgeAnimator == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.stepBadgeAnimation()
        }
        badgeAnimator = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepBadgeAnimation() {
        let target: CGFloat = isBadgePressed ? 0.94 : (isBadgeHovering ? 1.06 : 1)
        badgeVisualScale += (target - badgeVisualScale) * 0.28
        badgeAppearProgress = min(1, badgeAppearProgress + 1.0 / 60 / 0.28)
        needsDisplay = true
        if abs(target - badgeVisualScale) < 0.002 && badgeAppearProgress >= 1 {
            badgeVisualScale = target
            badgeAnimator?.invalidate()
            badgeAnimator = nil
        }
    }

    /// 미리보기에서 펼친 모습을 그리기 위한 문. 창 크기 조정 콜백은 부르지 않는다.
    func setExpandedForPreview(_ expanded: Bool) {
        isRibbonExpanded = expanded
        needsDisplay = true
    }

    /// 화면 없이 렌더할 때는 등장 애니메이션을 기다릴 수 없으니 곧바로 제자리로 보낸다.
    func settleAnimations() {
        badgeAnimator?.invalidate()
        badgeAnimator = nil
        badgeAppearProgress = 1
        badgeVisualScale = 1
        finishTyping()
        needsDisplay = true
    }

    /// 효과와 포즈를 함께 검수하는 오프스크린 시트용 프레임 고정값이다.
    /// 실제 타이머·상태 전환에는 쓰지 않는다.
    func setFrameForPreview(_ frame: Int) {
        let count = max(1, currentAnimation?.frames ?? 1)
        frameIndex = min(max(frame, 0), count - 1)
        needsDisplay = true
    }

    /// 시선 행을 실제 렌더 경로로 점검하는 오프스크린 미리보기 전용 설정값이다.
    func setGazeDirectionForPreview(_ direction: Int) {
        lookDirection = min(max(direction, 0), gazeDirectionCount - 1)
        needsDisplay = true
    }

    private func updateAccessibility() {
        let animation = animationCatalog[state] ?? animationCatalog[.idle]!
        let selection = isPinned ? "고정한 세션" : "자동 선택 세션"
        let attention = inputCount > 0 ? " 입력 필요 \(inputCount)개." : (attentionCount > 0 ? " 새 알림 \(attentionCount)개." : "")
        let connection = connectionStatus.map { " 연결 상태: \($0)." } ?? ""
        // 말풍선 내용도 읽어 준다. 소리로만 듣는 경우 이게 유일한 통로다.
        let spoken = bodyText()
        let message = spoken.isEmpty ? "" : " \(String(spoken.prefix(160)))."
        let source = payload?.sourceLabel ?? "AI"
        setAccessibilityLabel("\(source), \(payload?.project ?? "AI 작업"), \(animation.title).\(message) \(selection), 총 \(sessionCount)개 세션.\(attention)\(connection)")
    }

    /// 지금 그려야 하는 동작. 끄는 중이면 달리기가 상태를 이긴다.
    private var allowsGaze: Bool {
        if skin == .angelWings,AngelSkin.available{return AngelInteractions.hasGaze && visibleState == .idle && dragRun == nil && !sleepPose && transientState == nil}
        if skin == .amuRan { return visibleState == .idle && dragRun == nil && transientState == nil }
        if skin == .hachupingping { return visibleState == .idle && dragRun == nil && !sleepPose && transientState == nil }
        if skin == .howl { return false }
        if skin == .classic, ClassicGrown.available { return dragRun == nil && !sleepPose && transientState == nil && gazeStates.contains(visibleState) }
        if skin == .hana { return HanaGaze.allows(state: visibleState, dragging: dragRun != nil) && transientState == nil }
        guard skin != .hana, skin != .chocolatHeart, skin != .pichiPitch,
              gazeStates.contains(state), transientState == nil else { return false }
        return skin != .jeanne || (visibleState == .idle && dragRun == nil)
    }
    private var hasActiveGaze: Bool { (skin != .angelWings || allowsGaze) && (skin != .amuRan || allowsGaze) && skin != .howl && lookDirection != nil && (skin != .hachupingping || allowsGaze) && ((skin != .jeanne && skin != .hana) || allowsGaze) }

    private var currentAnimation: Animation? {
        if skin == .angelWings,AngelSkin.available {
            if let d=dragRun,let a=dragRunAnimations[d]{return AngelInteractions.animation(a)}
            if let a=animationCatalog[visibleState]{return AngelSkin.animation(a)}
        }
        if skin == .hachupingping, let a = dragRun.flatMap({dragRunAnimations[$0]}) ?? animationCatalog[visibleState] { return HachupingSkin.animation(a,key:hachupingKey) }
        if skin == .howl, let a = dragRun.flatMap({dragRunAnimations[$0]}) ?? animationCatalog[visibleState] { return HowlSkin.animation(a) }
        if skin == .classic, ClassicGrown.available,
           let selected = dragRun.flatMap({ dragRunAnimations[$0] }) ?? animationCatalog[visibleState] {
            return ClassicGrown.animation(selected)
        }
        if let dragRun, let animation = dragRunAnimations[dragRun] { return skin == .chocolatHeart ? ChocolatHeart.animation(animation) : skinAnimation(animation, skin: skin, columns: spriteLayout.columns) }
        guard let animation = animationCatalog[visibleState] else { return nil }
        return skin == .chocolatHeart ? ChocolatHeart.animation(animation) : skinAnimation(animation, skin: skin, columns: spriteLayout.columns)
    }

    private func restartAnimation() {
        if skin == .angelWings{angelLastDisplaySample=nil;angelEpoch=ProcessInfo.processInfo.systemUptime;angelIdleChoice.reset();angelLastMouseLocation=nil}
        if skin == .classic, let selected = currentAnimation {
            classicGrownEpoch = ProcessInfo.processInfo.systemUptime
                - ClassicGrown.elapsed(row: selected.row, frame: frameIndex, cycles: completedCycles)
        }
        let effectState = dragRun.map { String(describing: $0) } ?? visibleState.rawValue
        if effectState != christmasEffectState {
            christmasEffectState = effectState
            christmasEffectsStart = ProcessInfo.processInfo.systemUptime
            chocolatEpoch = ProcessInfo.processInfo.systemUptime
        }
        animationTimer?.invalidate()
        if skin == .amuRan {
            _=amuChoice.enter(state,session:payload?.id ?? "",turn:payload?.turnId ?? "")
            if state == .waving { spriteRestState=nil }
            amuRanPoseEpoch = ProcessInfo.processInfo.systemUptime
        }
        guard let animation = currentAnimation else { return }
        if skin == .hachupingping {
            let key=hachupingKey
            if key != hachupingLastKey { frameIndex=0;completedCycles=0;hachupingEffectsEpoch=ProcessInfo.processInfo.systemUptime;hachupingLastKey=key }
            hachupingEpoch=ProcessInfo.processInfo.systemUptime-Double(completedCycles*animation.frames+frameIndex)*animation.interval
        }
        if skin == .howl {
            if animation.row == 4 && howlLastRow != 4 { howlCookingB = Bool.random() }
            howlLastRow = animation.row
            howlEpoch = ProcessInfo.processInfo.systemUptime - HowlSkin.elapsed(row:animation.row,frame:frameIndex,cycles:completedCycles)
        }
        let poseTiming = skin == .christmas && spriteLayout.columns == 16
            ? Christmas16Timing.frameDuration(row: animation.row, frame: frameIndex) : nil
        if skin == .jeanne {
            jeanneEpoch = ProcessInfo.processInfo.systemUptime - JeanneSkin.elapsed(row: animation.row, frame: frameIndex, cycles: completedCycles)
        }
        if skin == .pichiPitch {
            pichiEpoch = ProcessInfo.processInfo.systemUptime - PichiSkin.elapsed(row: animation.row, frame: frameIndex, cycles: completedCycles)
        }
        if skin == .hana {
            hanaAnimationStart = ProcessInfo.processInfo.systemUptime - Double(completedCycles * animation.frames + frameIndex) * animation.interval
        }
        let timer = Timer(timeInterval: skin == .angelWings && AngelSkin.available ? 0.05 : skin == .hachupingping || skin == .howl || (skin == .classic && ClassicGrown.available) ? 1.0 / 60 : skin == .jeanne ? 0.05 : (skin == .amuRan || skin == .hana || skin == .chocolatHeart || skin == .pichiPitch) ? 1.0 / 60 : (poseTiming ?? animation.interval), repeats: poseTiming == nil) { [weak self] _ in
            self?.advanceFrame()
            if poseTiming != nil { self?.restartAnimation() }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    private func restartChristmasEffects() {
        christmasEffectsTimer?.invalidate()
        christmasEffectsTimer = nil
        guard skin == .christmas else { return }
        christmasEffectsStart = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        christmasEffectsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func setDragRunForPreview(_ direction: DragRun?) {
        dragRun = direction
        restartAnimation()
    }

    func setChristmasTimeForPreview(_ time: TimeInterval) {
        christmasPreviewTime = time
        needsDisplay = true
    }

    func validateJeanneStateTransitions() -> Bool {
        for state in PetState.allCases {
            guard let data = "{\"state\":\"\(state.rawValue)\",\"sessionId\":\"jeanne-state-fixture\"}".data(using:.utf8),
                  let payload = try? JSONDecoder().decode(StatePayload.self,from:data) else { return false }
            apply(payload,state:state,sessionCount:1,attentionCount:0,isPinned:false)
            guard currentAnimation?.row == animationCatalog[state]?.row else { return false }
            guard allowsGaze == (state == .idle) else { print("Unexpected gaze policy: \(state)"); return false }
            if state != .idle {
                lookDirection = 8
                guard !hasActiveGaze else { return false }
            }
            let duration = JeanneSkin.state(row: animationCatalog[state]!.row)!.cycle
            jeanneEpoch = ProcessInfo.processInfo.systemUptime - duration * 3 - 0.01
            advanceFrame()
            guard visibleState == state, currentAnimation?.row == animationCatalog[state]?.row else { print("State changed unexpectedly: \(state)"); return false }
        }
        clearGaze()
        guard let payload = try? JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"waving\",\"sessionId\":\"fixture\"}".utf8)) else { return false }
        apply(payload,state:.waving,sessionCount:1,attentionCount:0,isPinned:false)
        playReaction()
        guard transientState == .jumping, !allowsGaze, currentAnimation?.row == animationCatalog[.jumping]?.row else { return false }
        jeanneEpoch = ProcessInfo.processInfo.systemUptime - JeanneSkin.state(row:4)!.cycle - 0.01
        advanceFrame()
        guard transientState == nil, visibleState == .waving, currentAnimation?.row == 3 else { return false }
        for direction in [DragRun.right,.left] {
            dragRun = direction; restartAnimation()
            guard let a = currentAnimation, a.row == dragRunAnimations[direction]?.row, a.frames == 16 else { return false }
            jeanneEpoch = ProcessInfo.processInfo.systemUptime - 2.1
            advanceFrame()
            guard frameIndex < 16 else { return false }
        }
        dragRun = nil
        apply(payload,state:.idle,sessionCount:1,attentionCount:0,isPinned:false)
        for direction in 0..<16 { setGazeDirectionForPreview(direction); guard lookDirection == direction, hasActiveGaze else { return false } }
        clearGaze()
        apply(payload,state:.idle,sleepPose:true,sessionCount:1,attentionCount:0,isPinned:false)
        guard visibleState == .sleeping, !allowsGaze, currentAnimation?.row == 11 else { return false }
        apply(payload,state:.idle,sleepPose:false,sessionCount:1,attentionCount:0,isPinned:false)
        return lookDirection == nil && allowsGaze && currentAnimation?.row == 0
    }

    private func advanceFrame() {
        if skin == .angelWings {
            if visibleState == .idle && dragRun == nil && !hasActiveGaze {
                angelIdleChoice.choose(cycle:Int(floor(max(0,ProcessInfo.processInfo.systemUptime-angelEpoch)/3.2)))
            }
            if let window,window.isVisible {
                let cursor=NSEvent.mouseLocation
                if let previous=angelLastMouseLocation,hypot(cursor.x-previous.x,cursor.y-previous.y)>0.5 {
                    updateAngelGaze(at:convert(window.convertPoint(fromScreen:cursor),from:nil))
                }
                angelLastMouseLocation=cursor
            }
        }
        if skin == .hana {
            needsDisplay = true
            if let window, window.isVisible {
                let cursor = NSEvent.mouseLocation
                if let previous = hanaLastMouseLocation, hypot(cursor.x - previous.x, cursor.y - previous.y) > 0.5 {
                    updateHanaGaze(at: convert(window.convertPoint(fromScreen: cursor), from: nil))
                }
                hanaLastMouseLocation = cursor
            }
        }
        if skin == .angelWings, let animation = currentAnimation {
            let time = ProcessInfo.processInfo.systemUptime - angelEpoch
            let sample = AngelSkin.displaySample(row: animation.row, time: time,
                alternateIdle: visibleState == .idle && angelIdleChoice.variant == 1,
                flight: dragRun != nil)
            if hasActiveGaze || sample == nil || sample != angelLastDisplaySample { needsDisplay = true }
            angelLastDisplaySample = sample
        }
        if skin == .hachupingping || skin == .howl || skin == .amuRan || skin == .jeanne { needsDisplay = true }
        guard dragRun != nil || !hasActiveGaze, let animation = currentAnimation else { return }
        if skin == .angelWings,AngelSkin.available,dragRun == nil || AngelInteractions.hasFlight {
            let elapsed=ProcessInfo.processInfo.systemUptime-angelEpoch
            let p=dragRun == nil ? AngelSkin.position(row:animation.row,time:elapsed):AngelInteractions.position(row:animation.row,time:elapsed)
            frameIndex=p.frame;completedCycles=p.cycles
        } else if skin == .hachupingping {
            let p=HachupingSkin.position(hachupingKey,time:ProcessInfo.processInfo.systemUptime-hachupingEpoch)
            frameIndex=p.frame;completedCycles=p.cycles
        } else if skin == .howl {
            let p = HowlSkin.position(row:animation.row,time:ProcessInfo.processInfo.systemUptime-howlEpoch)
            frameIndex = p.frame; completedCycles = p.cycles
        } else if skin == .classic, ClassicGrown.available {
            let p = ClassicGrown.position(row: animation.row,
                elapsed: ProcessInfo.processInfo.systemUptime - classicGrownEpoch)
            frameIndex = p.frame; completedCycles = p.cycles
        } else if skin == .jeanne {
            if dragRun == nil && hasActiveGaze { return }
            let p = JeanneSkin.position(row: animation.row, time: ProcessInfo.processInfo.systemUptime - jeanneEpoch)
            frameIndex = p.frame; completedCycles = p.cycles
        } else if skin == .pichiPitch {
            let p = PichiSkin.position(row: animation.row, time: ProcessInfo.processInfo.systemUptime - pichiEpoch)
            frameIndex = p.frame; completedCycles = p.cycles
        } else if skin == .chocolatHeart {
            let tick = Int(max(0, ProcessInfo.processInfo.systemUptime - chocolatEpoch) / animation.interval)
            frameIndex = tick % animation.frames; completedCycles = tick / animation.frames
        } else if skin == .amuRan {
            let p = AmuRanMotion.position(elapsed: ProcessInfo.processInfo.systemUptime - amuRanPoseEpoch, interval: animation.interval)
            frameIndex = p.frame; completedCycles = p.cycles
        } else if skin == .hana {
            // 타이머 호출이 늦어져도 실제 경과 시간의 프레임으로 진행한다.
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - hanaAnimationStart)
            let position = HanaMotion.position(elapsed: elapsed, interval: animation.interval, frames: animation.frames)
            frameIndex = position.frame
            completedCycles = position.cycles
        } else {
            frameIndex = (frameIndex + 1) % animation.frames
            if frameIndex == 0 { completedCycles += 1 }
        }
        // 반응은 한 바퀴만 돌고 실제 상태로 돌아간다.
        if transientState != nil, completedCycles >= 1 {
            transientState = nil
            frameIndex = 0
            completedCycles = 0
            restartAnimation()
            return
        }
        if let limit = animation.cycleLimit, completedCycles >= limit {
            // 그림만 쉬는 자세로 앉힌다. 세션 상태는 훅이 다음 소식을 줄 때까지 그대로 둔다.
            spriteRestState = .idle
            frameIndex = 0
            completedCycles = 0
            restartAnimation()
            return
        }
        if skin != .angelWings { needsDisplay = true }
    }

    /// 몸통을 눌렀을 때의 반응. 코덱스 펫이 마우스를 올릴 때 쓰는 jumping 을 클릭 반응으로 쓴다.
    /// 우리는 창이 레토만큼 작아서 hover 를 반응에 쓰면 시선 추적을 잃는다.
    func validateHowlTransitions() -> Bool {
        guard skin == .howl else { return false }
        for s in PetState.allCases {
            let data = Data("{\"state\":\"\(s.rawValue)\",\"sessionId\":\"howl-state-fixture\"}".utf8)
            guard let payload = try? JSONDecoder().decode(StatePayload.self,from:data) else { return false }
            apply(payload,state:s,sessionCount:1,attentionCount:0,isPinned:false)
            guard let a = currentAnimation, a.row == HowlSkin.normalized(animationCatalog[s]!.row), !allowsGaze else { return false }
            lookDirection = 8
            guard !hasActiveGaze else { return false }
            howlEpoch = ProcessInfo.processInfo.systemUptime - HowlSkin.state(row:a.row)!.cycle * 2.1
            let heldVariant = howlCookingB
            advanceFrame()
            let expected: PetState = a.cycleLimit.map({ $0 <= 2 ? PetState.idle : s }) ?? s
            guard visibleState == expected, howlCookingB == heldVariant else { print("Howl return mismatch: \(s.rawValue)"); return false }
        }
        lookDirection = nil
        for d in [DragRun.left, .right] {
            setDragRunForPreview(d)
            guard currentAnimation?.row == (d == .right ? 1 : 2) else { return false }
        }
        setDragRunForPreview(nil)
        playReaction()
        guard transientState == .jumping, currentAnimation?.row == 4 else { return false }
        let variant = howlCookingB
        for _ in 0..<4 { advanceFrame(); guard howlCookingB == variant else { return false } }
        howlEpoch = ProcessInfo.processInfo.systemUptime - 3.21
        advanceFrame()
        guard transientState == nil, currentAnimation?.row == 11 else { return false }
        print("Howl native state/review/drag/unsupported-gaze/reaction-return and stable cooking choice: passed")
        return true
    }

    func validateHachupingTransitions() -> Bool {
        guard skin == .hachupingping else{return false}
        func enter(_ s:PetState,_ session:String="fixture",sleep:Bool=false) {
            let p=try! JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"\(s.rawValue)\",\"sessionId\":\"\(session)\"}".utf8))
            apply(p,state:s,sleepPose:sleep,sessionCount:1,attentionCount:0,isPinned:false)
        }
        for s in PetState.allCases {
            enter(s);guard currentAnimation?.frames == 16,allowsGaze == (s == .idle)else{print("Hachu mapping",s);return false}
            let held=hachupingPolicy.workingKey
            if s == .running { enter(.review);guard hachupingPolicy.workingKey==held else{return false} }
        }
        enter(.waiting);guard hachupingKey=="harp"else{return false}
        enter(.failed);guard hachupingKey=="failed"else{return false}
        enter(.waving);guard hachupingKey=="princess",currentAnimation?.cycleLimit==nil else{return false}
        for t in [6.5,9.9,60.7] {
            hachupingEpoch=ProcessInfo.processInfo.systemUptime-t;advanceFrame()
            guard visibleState == .waving,hachupingKey=="princess",spriteRestState==nil,frameIndex==HachupingSkin.position("princess",time:t).frame else{print("Completion stopped after",t);return false}
        }
        skin = .howl;spriteRestState = .idle;skin = .hachupingping
        guard visibleState == .waving,hachupingKey=="princess",spriteRestState==nil else{return false}
        print("Completion stays animated beyond 2/3/18 loops; selecting from rested other skin resumes Princess")
        playReaction();guard transientState == .jumping,hachupingKey=="jump",!allowsGaze else{return false}
        hachupingEpoch=ProcessInfo.processInfo.systemUptime-3.21;advanceFrame()
        guard transientState==nil,hachupingKey=="princess"else{return false}
        enter(.idle)
        for t in [0.1,1.7,6.5,13.3] {
            hachupingEpoch=ProcessInfo.processInfo.systemUptime-t;advanceFrame()
            guard visibleState == .idle,hachupingKey=="idle",frameIndex==HachupingSkin.position("idle",time:t).frame else{print("Idle playback failure",t);return false}
        }
        updateGaze(toward:4);guard hasActiveGaze,lookDirection==4 else{return false}
        clearGaze();guard !hasActiveGaze,currentAnimation?.frames==16 else{return false}
        hachupingEpoch=ProcessInfo.processInfo.systemUptime-1.7;advanceFrame()
        guard frameIndex==HachupingSkin.position("idle",time:1.7).frame else{return false}
        print("Actual RettoView independent idle advances across loops and resumes after cursor hold")
        for d in [DragRun.left,.right] {setDragRunForPreview(d);guard currentAnimation?.interval==0.1,!allowsGaze else{return false}}
        setDragRunForPreview(nil);guard hachupingKey=="idle"else{return false}
        for d in 0..<16 {updateGaze(toward:d);gazeTransitionTimer?.invalidate();gazeTransitionTimer=nil;lookDirection=d;guard hasActiveGaze else{return false}}
        scheduleGazeReset();RunLoop.main.run(until:Date(timeIntervalSinceNow:0.9));guard lookDirection==nil,hachupingKey=="idle"else{return false}
        enter(.idle,sleep:true);guard hachupingKey=="sleeping",!allowsGaze,currentAnimation?.interval==0.4 else{return false}
        enter(.idle,sleep:false);guard allowsGaze else{return false}
        print("Hachuping actual RettoView: working/review, all states, completion, reaction return, both drags, 16 gaze cells/reset and sleep passed")
        return true
    }
    func validateAmuApprovedTransitions() -> Bool {
        guard skin == .amuRan,AmuApproved.validate() else{return false}
        for s in PetState.allCases {
            let data=Data("{\"state\":\"\(s.rawValue)\",\"sessionId\":\"amu-approved-fixture\"}".utf8)
            guard let p=try? JSONDecoder().decode(StatePayload.self,from:data) else{return false}
            apply(p,state:s,sessionCount:1,attentionCount:0,isPinned:false)
            guard let a=currentAnimation,a.frames==16,let key=AmuApproved.key(row:a.row),
                  abs(a.interval*16-(AmuApproved.manifest?.states[key]?.cycle ?? -1))<0.000001,
                  allowsGaze == (s == .idle) else{print("Amu state mismatch",s);return false}
        }
        for direction in [DragRun.left,.right] {
            setDragRunForPreview(direction)
            guard currentAnimation?.row == (direction == .right ? 1:2),!allowsGaze else{return false}
        }
        setDragRunForPreview(nil)
        playReaction()
        guard transientState == .jumping,currentAnimation?.row==4,!allowsGaze else{return false}
        amuRanPoseEpoch=ProcessInfo.processInfo.systemUptime-3.21
        advanceFrame()
        guard transientState==nil,currentAnimation?.row==11 else{print("Amu click did not return to sleep");return false}
        print("PASS actual Amu state/review alias,16-frame clocks,drag,gaze gates,click return to sleep")
        return true
    }
    func validateAmuRandomStates() -> Bool {
        guard skin == .amuRan,AmuApproved.validateChoices() else{return false}
        func enter(_ s:PetState,_ message:String) {
            let data=try! JSONSerialization.data(withJSONObject:["state":s.rawValue,"sessionId":"amu-random-fixture","turnId":"one","lastAssistantMessage":message])
            let p=try! JSONDecoder().decode(StatePayload.self,from:data)
            apply(p,state:s,sessionCount:1,attentionCount:0,isPinned:false)
        }
        enter(.running,"start")
        let work=amuChoice.working
        guard AmuApproved.Choice.workingPool.contains(work) else{return false}
        amuRanPoseEpoch=ProcessInfo.processInfo.systemUptime-1.1
        let phase=amuRanPoseEpoch
        for (i,s) in [PetState.review,.running,.review,.running].enumerated() {
            enter(s,"work refresh \(i)")
            guard amuChoice.working==work,currentAnimation?.row==7,abs(amuRanPoseEpoch-phase)<0.02 else{print("Work refresh rerolled/reset");return false}
        }
        enter(.waving,"complete")
        let done=amuChoice.completion
        guard AmuApproved.Choice.completionPool.contains(done),currentAnimation?.cycleLimit==nil else{return false}
        for t in [6.5,9.9,60.7] {
            amuRanPoseEpoch=ProcessInfo.processInfo.systemUptime-t;advanceFrame()
            let epoch=amuRanPoseEpoch
            enter(.waving,"completion refresh \(t)")
            guard visibleState == .waving,spriteRestState==nil,currentAnimation?.row==3,
                  amuChoice.completion==done,abs(amuRanPoseEpoch-epoch)<0.02 else{print("Completion became idle/rerolled after",t);return false}
        }
        playReaction();amuRanPoseEpoch=ProcessInfo.processInfo.systemUptime-3.21;advanceFrame()
        guard transientState==nil,visibleState == .waving,amuChoice.completion==done,currentAnimation?.cycleLimit==nil else{return false}
        print("PASS actual Amu: stable4-way work, review phase preserved, stable2-way completion beyond60s, no idle fallback, click returns to same completion")
        return true
    }
    func validateAngelTransitions()->Bool {
        guard skin == .angelWings,AngelSkin.validate() else{return false}
        func enter(_ s:PetState){
            let data=Data("{\"state\":\"\(s.rawValue)\",\"sessionId\":\"angel-state-fixture\"}".utf8)
            if let p=try? JSONDecoder().decode(StatePayload.self,from:data){apply(p,state:s,sessionCount:1,attentionCount:0,isPinned:false)}
        }
        for s in PetState.allCases {
            enter(s)
            guard let a=currentAnimation,let k=AngelSkin.key(row:a.row),let m=AngelSkin.manifest?.states[k],a.frames==16,abs(a.interval*16-m.cycle)<0.000001,allowsGaze == (s == .idle && AngelInteractions.hasGaze) else{print("Angel state mismatch",s);return false}
            setGazeDirectionForPreview(3);guard hasActiveGaze == allowsGaze else{return false};clearGaze()
        }
        enter(.running);let run=currentAnimation!;enter(.review)
        guard currentAnimation?.row==run.row,currentAnimation?.interval==run.interval else{return false}
        for d in [DragRun.left,.right]{setDragRunForPreview(d);guard currentAnimation?.row==(d == .right ? 1:2) else{return false}}
        setDragRunForPreview(nil);enter(.sleeping);playReaction()
        guard transientState == .jumping,currentAnimation?.row==4 else{return false}
        angelEpoch=ProcessInfo.processInfo.systemUptime-2.401;advanceFrame()
        guard transientState==nil,currentAnimation?.row==11 else{print("Angel click return failure");return false}
        print("PASS Angel actual state transitions,review-to-running alias,gaze gate,legacy drag,click returns to sleep")
        return true
    }
    func validateAngelInteractions()->Bool {
        guard AngelInteractions.validate() else{return false}
        guard let p=try? JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"idle\",\"sessionId\":\"angel-interaction-fixture\"}".utf8))else{return false}
        apply(p,state:.idle,sessionCount:1,attentionCount:0,isPinned:false)
        for d in 0..<16 {
            clearGaze()
            let pivot=AngelInteractions.point([255,215],in:AngelSkin.rect(row:0,in:layout.petRect))
            let a=Double(d)*Double.pi/8
            updateAngelGaze(at:NSPoint(x:pivot.x+CGFloat(sin(a))*200,y:pivot.y+CGFloat(cos(a))*200))
            guard lookDirection==d,hasActiveGaze else{print("Cursor sector failure",d,lookDirection as Any);return false}
        }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:gazeHoldDuration+0.15))
        guard lookDirection==nil,currentAnimation?.row==0,frameIndex<2 else{print("Gaze did not return to idle start");return false}
        for state in PetState.allCases where state != .idle {
            apply(p,state:state,sessionCount:1,attentionCount:0,isPinned:false)
            updateAngelGaze(at:NSPoint(x:1000,y:1000));guard !hasActiveGaze else{return false}
        }
        apply(p,state:.running,sessionCount:1,attentionCount:0,isPinned:false)
        for d in [DragRun.left,.right] {
            setDragRunForPreview(d)
            guard currentAnimation?.frames==16,currentAnimation?.interval==0.1,!allowsGaze else{return false}
            angelEpoch=ProcessInfo.processInfo.systemUptime-1.601;advanceFrame()
            guard frameIndex==0,completedCycles==1 else{print("Flight pose cadence mismatch");return false}
        }
        setDragRunForPreview(nil)
        guard currentAnimation?.row==7 || currentAnimation?.row==8 else{return false}
        print("PASS actual Angel cursor16sectors/hold/reset, working-state isolation, both16-pose airborne drag directions and return")
        return true
    }
    private func playReaction() {
        if skin == .howl { howlCookingB = Bool.random() }
        spriteRestState = nil
        transientState = .jumping
        clearGaze()
        frameIndex = 0
        completedCycles = 0
        restartAnimation()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard petClickTarget(layout: layout, badgeFrame: badgeFrame, point: local, attentionCount: attentionCount) != nil else { return nil }
        return super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    private func updateHover(at point: NSPoint) {
        let layout = self.layout
        let target = petClickTarget(layout: layout, badgeFrame: badgeFrame, point: point, attentionCount: attentionCount)

        let wasBadgeHovering = isBadgeHovering
        isBadgeHovering = target == .badge
        if isBadgeHovering != wasBadgeHovering { startBadgeAnimator() }

        let wasRibbonHovering = isRibbonHovering
        isRibbonHovering = target == .ribbon
        if isRibbonHovering != wasRibbonHovering {
            needsDisplay = true
            scheduleRibbonExpansion(isRibbonHovering)
        }

        // 배지와 말풍선은 누를 것, 몸통은 집을 것이라는 신호를 커서로 준다.
        switch target {
        case .badge, .ribbon: NSCursor.pointingHand.set()
        case .body: NSCursor.openHand.set()
        case nil: NSCursor.arrow.set()
        }

        if skin == .angelWings { updateAngelGaze(at:point);return }
        if skin == .hana { updateHanaGaze(at: point); return }
        guard allowsGaze else { return }
        let petRect = layout.petRect
        let dx = point.x - petRect.midX
        let dy = point.y - petRect.midY
        guard hypot(dx, dy) > 22 * petScale else { return }
        let direction = gazeDirection(dx: dx, dy: dy, previous: gazeTargetDirection ?? lookDirection)
        updateGaze(toward: direction)
        scheduleGazeReset()
        needsDisplay = true
    }

    func verifyHanaGazeBehaviorForTesting() -> Bool {
        guard skin == .hana else { return false }
        let point = NSPoint(x: layout.petRect.maxX + 100, y: layout.petRect.minY + layout.petRect.height * (1 - 260.0 / 640))
        updateHanaGaze(at: point)
        guard lookDirection == 4 else { return false }
        let before = HanaMotion.effectFrame(time: 0.1)
        guard before != HanaMotion.effectFrame(time: 0.8) else { return false }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: gazeHoldDuration + 0.12))
        guard lookDirection == nil, frameIndex < 2 else { return false }
        dragRun = .right
        updateHanaGaze(at: point)
        guard lookDirection == nil else { return false }
        dragRun = nil
        sleepPose = true
        updateHanaGaze(at: point)
        guard lookDirection == nil else { return false }
        sleepPose = false
        for testState in PetState.allCases where !gazeStates.contains(testState) {
            state = testState
            updateHanaGaze(at: point)
            guard lookDirection == nil else { return false }
        }
        for testState in gazeStates {
            state = testState
            updateHanaGaze(at: point)
            guard lookDirection == 4 else { return false }
            clearGaze()
        }
        state = .idle
        updateHanaGaze(at: point)
        guard lookDirection == 4 else { return false }
        playReaction()
        guard lookDirection == nil else { return false }
        return true
    }

    private func updateAngelGaze(at point:NSPoint) {
        guard allowsGaze else{return}
        let pivot=AngelInteractions.point([255,215],in:AngelSkin.rect(row:0,in:layout.petRect))
        let dx=point.x-pivot.x,dy=point.y-pivot.y
        guard hypot(dx,dy)>18*petScale else{return}
        updateGaze(toward:gazeDirection(dx:dx,dy:dy,previous:gazeTargetDirection ?? lookDirection))
        scheduleGazeReset();needsDisplay=true
    }
    private func updateHanaGaze(at point: NSPoint) {
        guard HanaGaze.allows(state: visibleState, dragging: dragRun != nil) else { return }
        let dx = point.x - layout.petRect.midX
        let dy = point.y - (layout.petRect.minY + layout.petRect.height * (1 - 260.0 / 640))
        guard hypot(dx, dy) > 22 * petScale else { return }
        updateGaze(toward: gazeDirection(dx: dx, dy: dy, previous: gazeTargetDirection ?? lookDirection))
        scheduleGazeReset()
        needsDisplay = true
    }

    /// 시선은 짧은 반응으로만 보이고, 커서가 멈추면 원래 idle 모션을 계속한다.
    private func scheduleGazeReset() {
        gazeResetTimer?.invalidate()
        let timer = Timer(timeInterval: gazeHoldDuration, repeats: false) { [weak self] _ in
            self?.clearGaze()
        }
        gazeResetTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateGaze(toward direction: Int) {
        gazeTargetDirection = direction
        guard (skin == .angelWings && AngelInteractions.hasGaze) || ((skin == .hachupingping || skin == .christmas || skin == .amuRan || skin == .hana) && spriteLayout.columns == 16) || (skin == .classic && ClassicGrown.gazeAvailable), lookDirection != nil else {
            lookDirection = direction
            return
        }
        guard lookDirection != direction, gazeTransitionTimer == nil else { return }
        let timer = Timer(timeInterval: christmasGazeStepDuration, repeats: true) { [weak self] _ in
            guard let self, let current = self.lookDirection, let target = self.gazeTargetDirection else { return }
            self.lookDirection = nextGazeDirection(from: current, toward: target)
            self.needsDisplay = true
            if self.lookDirection == target {
                self.gazeTransitionTimer?.invalidate()
                self.gazeTransitionTimer = nil
            }
        }
        gazeTransitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func clearGaze() {
        gazeResetTimer?.invalidate()
        gazeResetTimer = nil
        gazeTransitionTimer?.invalidate()
        gazeTransitionTimer = nil
        gazeTargetDirection = nil
        guard lookDirection != nil else { return }
        lookDirection = nil
        frameIndex = 0
        if skin == .angelWings { restartAnimation() }
        if skin == .classic && ClassicGrown.available { restartAnimation() }
        if skin == .amuRan { restartAnimation() }
        if skin == .hachupingping || skin == .christmas || skin == .hana { restartAnimation() }
        needsDisplay = true
    }

    /// 지나가는 마우스에 펼쳐지지 않게 잠깐 기다린다. 벗어나면 곧바로 접는다.
    private func scheduleRibbonExpansion(_ shouldExpand: Bool) {
        ribbonExpandTimer?.invalidate()
        ribbonExpandTimer = nil
        guard shouldExpand else {
            setRibbonExpanded(false)
            return
        }
        guard !bodyText().isEmpty else { return }
        // 문장이 짧아 이미 다 보이면 펼치지 않는다. 늘어난 만큼 빈 칸만 생긴다.
        guard !bodyFitsCollapsed() else { return }
        let timer = Timer(timeInterval: ribbonExpandDelay, repeats: false) { [weak self] _ in
            // 기다리는 사이에 문장이 짧아졌을 수도 있다.
            guard let self, self.isRibbonHovering, !self.bodyFitsCollapsed() else { return }
            self.setRibbonExpanded(true)
        }
        ribbonExpandTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setRibbonExpanded(_ expanded: Bool) {
        guard isRibbonExpanded != expanded else { return }
        // 펼치면 안 보였던 뒷부분이 드러나므로 다시 찍지 않고 바로 다 보여준다.
        if expanded { finishTyping() }
        isRibbonExpanded = expanded
        onExpansionChanged?(expanded)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        scheduleRibbonExpansion(false)
        isRibbonHovering = false
        if isBadgeHovering {
            isBadgeHovering = false
            startBadgeAnimator()
        }
        NSCursor.arrow.set()
        clearGaze()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        let local = convert(event.locationInWindow, from: nil)
        pressedTarget = petClickTarget(layout: layout, badgeFrame: badgeFrame, point: local, attentionCount: attentionCount)
        didDrag = false
        if pressedTarget == .badge {
            isBadgePressed = true
            startBadgeAnimator()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouseLocation,
              let startOrigin = dragStartWindowOrigin else { return }
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - startMouse.x
        let deltaY = currentMouse.y - startMouse.y
        if hypot(deltaX, deltaY) >= 4 { didDrag = true }
        guard didDrag else { return }
        // 배지를 눌러 끌면 창이 움직이지 않게 막는다.
        if pressedTarget == .badge { return }
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY))
        // 코덱스 펫처럼 끌리는 방향으로 달린다. 방향은 직전 위치와의 차이로 정하고,
        // 2pt 를 넘지 않는 떨림은 무시한다 — 안 그러면 좌우가 매 프레임 뒤집힌다.
        let previousX = lastDragX ?? startMouse.x
        let step = currentMouse.x - previousX
        var next = dragRun
        if step > 2 { next = .right; lastDragX = currentMouse.x }
        else if step < -2 { next = .left; lastDragX = currentMouse.x }
        else if dragRun == nil { next = deltaX >= 0 ? .right : .left; lastDragX = currentMouse.x }
        if next != dragRun {
            dragRun = next
            // 시선 추적은 끄는 동안 쉰다. 손을 놓으면 다시 따라간다.
            clearGaze()
            frameIndex = 0
            completedCycles = 0
            restartAnimation()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let target = pressedTarget
        let dragged = didDrag
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            pressedTarget = nil
            didDrag = false
            if dragRun != nil {
                dragRun = nil
                lastDragX = nil
                frameIndex = 0
                completedCycles = 0
                restartAnimation()
            }
            if isBadgePressed {
                isBadgePressed = false
                startBadgeAnimator()
            }
        }

        guard !dragged else { return }

        switch target {
        case .badge:
            // 배지는 여러 세션을 대표하므로 하나를 골라 열 수 있게 목록을 배지 바로 아래 띄운다.
            onOpenAttention(NSPoint(x: badgeFrame.midX, y: badgeFrame.minY))
        case .ribbon:
            onOpenClaude(payload, event.modifierFlags.contains(.option))
        case .body:
            // 코덱스 펫은 클릭하면 현재 창을 띄우고 입력창에 포커스한다(open-current-main-window).
            // 여기서는 그 세션이 사는 창을 앞으로 보내고 그 탭까지 되살린다. ⌥ 면 창만.
            playReaction()
            onOpenClaude(payload, event.modifierFlags.contains(.option))
        case nil:
            break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 스프라이트는 반응 상태를 따르고, 말풍선과 배지 색은 실제 상태를 지킨다.
        guard let animation = animationCatalog[visibleState],
              let statusAnimation = animationCatalog[state] else { return }

        let layout = self.layout
        let uiScale = layout.petScale
        let petRect = layout.petRect
        let row: Int
        let column: Int
        if let dragRun, let run = dragRunAnimations[dragRun] {
            row = run.row
            column = frameIndex
        } else if let direction = lookDirection, hasActiveGaze {
            if skin == .hachupingping { row=9;column=direction }
            else if skin == .amuRan {
                row = AmuRanMotion.gazeRow(state: visibleState); column = direction
            } else {
                row = direction < 8 ? 9 : 10
                column = direction < 8 ? direction : direction - 8
            }
        } else {
            // v2 개인 스킨은 11행이라 레토 전용 잠자기 행이 없다. idle 자세에 호흡 효과를
            // 더해 잠든 모습을 유지한다. 나머지 상태와 시선 행은 같은 순서다.
            row = visibleState == .sleeping && spriteLayout.rows == 11 ? 0 : animation.row
            column = frameIndex
        }
        let sourceRect = NSRect(
            x: CGFloat(column) * spriteLayout.cellWidth,
            y: spriteLayout.sheetHeight - CGFloat(row + 1) * spriteLayout.cellHeight,
            width: spriteLayout.cellWidth,
            height: spriteLayout.cellHeight
        )


        // 발밑 바닥 그림자. 예전에는 실루엣 드롭 섀도(blur 16)를 썼는데, 흐림이 사방으로
        // 퍼져 머리 위에도 회색 안개가 생겼다. 흰 배경에서는 그게 투명한 사각형처럼 보였다.
        // 동물의 숲처럼 발밑에만 타원을 깔고, 몸에는 아주 얕은 그림자만 남긴다.
        if !(skin == .angelWings && dragRun != nil && AngelInteractions.hasFlight) {
            drawGroundShadow(petRect: petRect, scale: uiScale)
        }

        let amuRect = AmuApproved.registeredRect(row:row,in:petRect,workingKey:amuChoice.working,completionKey:amuChoice.completion)
        let amuEffectsRect = AmuApproved.registeredRect(row:AmuRanMotion.row(state:visibleState,drag:dragRun),in:petRect,workingKey:amuChoice.working,completionKey:amuChoice.completion)
        let amuRanTime = amuRanPreviewTime ?? (ProcessInfo.processInfo.systemUptime - amuRanEffectEpoch)
        let amuRanPoseTime = amuRanPreviewTime ?? (ProcessInfo.processInfo.systemUptime - amuRanPoseEpoch)
        if skin == .amuRan { AmuRanFrames.drawEffects(state: visibleState, drag: dragRun, time: amuRanTime, poseTime: amuRanPoseTime, gazeDirection: dragRun == nil ? lookDirection : nil, in: amuEffectsRect, front: false,workingKey:amuChoice.working,completionKey:amuChoice.completion) }
        let hachuDrawKey = skin == .hachupingping && hasActiveGaze && dragRun == nil ? "gaze":hachupingKey
        let hachuTime = hachupingPreviewTime ?? (ProcessInfo.processInfo.systemUptime-hachupingEffectsEpoch)
        if skin == .hachupingping { HachupingSkin.drawEffects(key:hachuDrawKey,time:hachuTime,front:false,in:petRect) }
        let howlTime = howlPreviewTime ?? (ProcessInfo.processInfo.systemUptime-howlEpoch)
        if skin == .howl { HowlSkin.drawEffects(row:row,frame:column,time:howlTime,cookingB:howlCookingB,front:false,in:petRect) }
        let jeanneTime = jeannePreviewTime ?? (ProcessInfo.processInfo.systemUptime - jeanneEpoch)
        if skin == .jeanne { JeanneSkin.drawEffects(row: row, frame: column, time: jeanneTime, front: false, in: petRect) }
        let pichiTime = pichiPreviewTime ?? (ProcessInfo.processInfo.systemUptime - pichiEpoch)
        if skin == .pichiPitch { PichiSkin.drawEffects(row: row, time: pichiTime, front: false, in: petRect) }
        let christmasTime = christmasPreviewTime ?? (ProcessInfo.processInfo.systemUptime - christmasEffectsStart)
        if skin == .christmas {
            drawChristmasEffects(state: visibleState, drag: dragRun, gaze: lookDirection != nil,
                                 in: petRect, time: christmasTime, frame: frameIndex, front: false)
        }

        if skin == .hana {
            hanaEffects.draw(state: hasActiveGaze && dragRun == nil ? .idle : visibleState, drag: dragRun, in: petRect, time: christmasTime, front: false)
        }

        if skin == .chocolatHeart {
            ChocolatHeart.drawEffects(row: row, time: chocolatPreviewTime ?? (ProcessInfo.processInfo.systemUptime - chocolatEpoch), front: false, in: petRect)
        }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = skin == .angelWings && AngelSkin.available ? NSColor.clear:NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 5 * uiScale
        shadow.shadowOffset = NSSize(width: 0, height: -2 * uiScale)
        shadow.set()
        if skin == .angelWings,AngelSkin.available,dragRun == nil || AngelInteractions.hasFlight {
            let t=angelPreviewTime ?? (ProcessInfo.processInfo.systemUptime-angelEpoch)
            if hasActiveGaze,let d=lookDirection {
                _=AngelInteractions.drawGaze(direction:d,time:t,in:petRect)
            }else if dragRun != nil,let key=AngelInteractions.flightKey(row) {
                _=AngelInteractions.draw(key:key,time:t,in:petRect)
            }else {
                if visibleState == .idle {angelIdleChoice.choose(cycle:Int(floor(max(0,t)/3.2)))}
                if visibleState == .idle && angelIdleChoice.variant==1 && AngelInteractions.hasIdle {
                    _=AngelInteractions.draw(key:"idle-look",time:t,in:petRect)
                }else{_=AngelSkin.draw(row:row,time:t,in:petRect)}
            }
        } else if skin == .hachupingping {
            HachupingSkin.drawCharacter(key:hachuDrawKey,frame:column,in:petRect)
        } else if skin == .howl {
            HowlSkin.drawCharacter(row:row,frame:column,cookingB:howlCookingB,in:petRect)
        } else if skin == .classic, ClassicGrown.available {
            _ = ClassicGrown.draw(row: row, frame: column, in: petRect)
        } else if skin == .amuRan {
            _ = AmuRanFrames.drawCharacter(row: row, frame: column, in: amuRect, poseTime: amuRanPoseTime,workingKey:amuChoice.working,completionKey:amuChoice.completion)
        } else if skin == .jeanne {
            JeanneSkin.drawCharacter(row: row, frame: column, in: petRect)
        } else if skin == .pichiPitch {
            PichiSkin.drawCharacter(row: row, frame: column, in: petRect)
        } else if skin == .chocolatHeart {
            ChocolatHeart.drawCharacter(row: row, frame: column, in: petRect)
        } else if skin != .hana || !HanaFrameCache.drawCharacter(row: row, frame: column, in: petRect) {
            spriteSheet.draw(in: petRect, from: sourceRect, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        }
        NSGraphicsContext.restoreGraphicsState()

        if skin == .christmas {
            drawChristmasEffects(state: visibleState, drag: dragRun, gaze: lookDirection != nil,
                                 in: petRect, time: christmasTime, frame: frameIndex, front: true)
        }

        if skin == .hana {
            hanaEffects.draw(state: hasActiveGaze && dragRun == nil ? .idle : visibleState, drag: dragRun, in: petRect, time: christmasTime, front: true)
        }


        if skin == .chocolatHeart {
            ChocolatHeart.drawEffects(row: row, time: chocolatPreviewTime ?? (ProcessInfo.processInfo.systemUptime - chocolatEpoch), front: true, in: petRect)
        }
        if skin == .jeanne { JeanneSkin.drawEffects(row: row, frame: column, time: jeanneTime, front: true, in: petRect) }
        if skin == .pichiPitch { PichiSkin.drawEffects(row: row, time: pichiTime, front: true, in: petRect) }
        if skin == .amuRan { AmuRanFrames.drawEffects(state: visibleState, drag: dragRun, time: amuRanTime, poseTime: amuRanPoseTime, gazeDirection: dragRun == nil ? lookDirection : nil, in: amuEffectsRect, front: true,workingKey:amuChoice.working,completionKey:amuChoice.completion) }
        if skin == .howl { HowlSkin.drawEffects(row:row,frame:column,time:howlTime,cookingB:howlCookingB,front:true,in:petRect) }
        if skin == .hachupingping { HachupingSkin.drawEffects(key:hachuDrawKey,time:hachuTime,front:true,in:petRect) }
        if visibleState == .sleeping && skin != .angelWings && skin != .hachupingping && skin != .howl && skin != .amuRan && skin != .jeanne && skin != .hana && skin != .chocolatHeart && skin != .pichiPitch {
            drawSleepBreath(petRect: petRect, scale: uiScale)
        }

        if skin != .amuRan || !amuRanSpriteOnlyPreview { drawStatusRibbon(statusAnimation, layout: layout) }
    }



    private func drawAttentionBadge(ribbon: NSRect, scale: CGFloat) {
        let appear = easeOutBack(badgeAppearProgress)
        let visualScale = badgeVisualScale * (0.7 + 0.3 * appear)
        let alpha = badgeAppearProgress

        var rect = attentionBadgeRect(ribbon: ribbon, scale: scale)
        if inputCount > 0 {
            let width = 65 * scale
            rect.origin.x -= width - rect.width
            rect.size.width = width
        }
        badgeFrame = rect.insetBy(dx: -2, dy: -2)
        rect = rect.insetBy(dx: rect.width * (1 - visualScale) / 2, dy: rect.height * (1 - visualScale) / 2)

        let ringWidth = chromeStrokeWidth(scale)
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -ringWidth, dy: -ringWidth), xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 * alpha)
        shadow.shadowBlurRadius = 4 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96 * alpha).setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()

        let circle = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let badgeTone = notificationTone(source: attentionSource, state: attentionState ?? .waving,
                                         fallback: attentionState == .waiting ? toneNeedsYou : toneDone)
        badgeTone.background.withAlphaComponent(0.97 * alpha).setFill()
        circle.fill()
        if isBadgePressed {
            NSColor.black.withAlphaComponent(0.12 * alpha).setFill()
            circle.fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "AvenirNext-DemiBold", size: 12 * scale * visualScale) ?? NSFont.boldSystemFont(ofSize: 12 * scale * visualScale),
            .foregroundColor: badgeTone.text.withAlphaComponent(alpha)
        ]
        let count = inputCount > 0 ? inputCount : attentionCount
        let number = count > 99 ? "99+" : "\(count)"
        let label = inputCount > 0 ? "입력 \(number)" : (count > 9 ? "9+" : number)
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawStatusRibbon(_ animation: Animation, layout: PetLayout) {
        let tone = notificationTone(source: payload?.source, state: state, fallback: animation.tone)
        let scale = layout.chromeScale
        let textDelta = layout.textDelta
        let ribbonRect = layout.ribbonRect
        // Figma 벡터 그대로의 구름형 말풍선. 색도 그 도형의 채우기 값(#FFFBE8)을 쓴다.
        // 흰 배경 위에서는 크림색 말풍선의 윤곽이 사라지므로 부드러운 그림자와 실선 한 겹을 깐다.
        let ribbon = bubblePath(in: ribbonRect)
        NSGraphicsContext.saveGraphicsState()
        let bubbleShadow = NSShadow()
        bubbleShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        bubbleShadow.shadowBlurRadius = 12 * scale
        bubbleShadow.shadowOffset = NSSize(width: 0, height: -2 * scale)
        bubbleShadow.set()
        hexColor(0xFFFBE8).withAlphaComponent(0.98).setFill()
        ribbon.fill()
        NSGraphicsContext.restoreGraphicsState()

        hexColor(0xE0D3A8).withAlphaComponent(0.55).setStroke()
        ribbon.lineWidth = chromeStrokeWidth(scale) * 0.8
        ribbon.stroke()

        // 동물의 숲 이름표. 말풍선 왼쪽 위 모서리에 반쯤 걸치고, 색이 지금 상태를 말한다.
        let nameStyle = NSMutableParagraphStyle()
        nameStyle.lineBreakMode = .byTruncatingTail
        // 이름표 글자색은 배경 밝기로 정한다. 진행 중의 노란 주황 위에서는 흰 글자가 읽히지 않는다.
        let nameAttributes: [NSAttributedString.Key: Any] = [
            // 이름표는 본문과 같은 글꼴, 크기만 1.5pt 작게.
            .font: petFont(typeface, size: 16.5 * scale + textDelta, bold: true),
            .foregroundColor: tone.text,
            .paragraphStyle: nameStyle
        ]
        let namePadding = 12 * scale
        let nameHeight = 28 * scale
        // 한글 12자 폭이 상한이다. 영문처럼 좁은 글자는 12자를 넘어도 이 폭까지는 다 보인다.
        let labelBudget = (sectionLabelWidthSample as NSString).size(withAttributes: nameAttributes).width
        // 오른쪽 배지와 부딧치지 않는 선까지만 허용한다.
        let badgeGuard = ribbonRect.width - 14 * scale - ((inputCount > 0 ? 65 : attentionBadgeSide) + 14) * scale - 10 * scale
        let nameTextBudget = min(labelBudget, max(40 * scale, badgeGuard - namePadding * 2))
        let name = fittedSingleLine(sectionLabel(), maxWidth: nameTextBudget, attributes: nameAttributes)
        let nameWidth = name.size(withAttributes: nameAttributes).width + namePadding * 2
        // 말풍선 위로 솟되 아래쪽 절반 가까이가 말풍선 안으로 들어가 한 덩어리로 붙어 보이게 한다.
        let nameRect = NSRect(
            x: ribbonRect.minX + 14 * scale,
            y: ribbonRect.maxY - nameHeight * namePillOverlap,
            width: nameWidth,
            height: nameHeight
        )

        NSGraphicsContext.saveGraphicsState()
        let nameShadow = NSShadow()
        nameShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        nameShadow.shadowBlurRadius = 4 * scale
        nameShadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
        nameShadow.set()
        let namePill = NSBezierPath(roundedRect: nameRect, xRadius: nameHeight / 2, yRadius: nameHeight / 2)
        tone.background.withAlphaComponent(0.97).setFill()
        namePill.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        namePill.lineWidth = chromeStrokeWidth(scale)
        namePill.stroke()

        if attentionCount > 0 {
            drawAttentionBadge(ribbon: ribbonRect, scale: scale)
        } else {
            badgeFrame = .zero
        }

        let nameSize = name.size(withAttributes: nameAttributes)
        // 손글씨는 글자 위쪽 여백이 넓게 잡혀 있어 가운데 정렬만 하면 위가 더 비어 보인다. 2pt 올려 맞춘다.
        // 기본 서체에는 그 여백이 없다. 같은 보정을 하면 반대로 글자가 위로 떠 버린다.
        let nameNudge = typeface == .handwriting ? 2 * scale : 0
        name.draw(
            in: NSRect(
                x: nameRect.minX + namePadding,
                y: nameRect.midY - nameSize.height / 2 + nameNudge,
                width: nameRect.width - namePadding * 2,
                height: nameSize.height
            ),
            withAttributes: nameAttributes
        )
        // 나머지 공간은 전부 멘트에 준다. 펼치면 아래로 더 자라고 그만큼 더 읽힌다.
        let messageAttributes = messageAttributes(scale: scale, textDelta: textDelta)
        var messageRect = messageRect(in: ribbonRect, scale: scale)
        if let connectionStatus {
            let lineHeight = 16 * scale
            messageRect.origin.y += lineHeight
            messageRect.size.height = max(0, messageRect.height - lineHeight)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5 * scale, weight: .medium),
                .foregroundColor: hexColor(0x925400), .paragraphStyle: style
            ]
            (connectionStatus as NSString).draw(in: NSRect(x: messageRect.minX, y: ribbonRect.minY + 9 * scale,
                width: messageRect.width, height: lineHeight), withAttributes: attributes)
        }
        let fullMessage = fullMessageText(for: animation)
        let bodyBox = bodyLineBox(in: messageRect, attributes: messageAttributes, scale: scale, textDelta: textDelta)
        let fittedFull = fittedBody(fullMessage, in: messageRect, attributes: messageAttributes, maxHeight: bodyBox.fit) as String
        let shownMessage = typedPortion(of: fittedFull, fullLength: fullMessage.count) as NSString
        // 보이는 글자를 다 찍었으면 타이머를 붙잡고 있을 이유가 없다.
        if typeTimer != nil, typedCount >= fittedFull.count { finishTyping() }
        // 글자는 칸 위에서부터 그려진다. 글꼴이 작으면 아래 여백만 남아 위로 쏠려 보이므로
        // 실제 차지하는 높이를 재서 말풍선 세로 가운데에 놓는다. 높이는 다 찍은 뒤 문장(`fittedFull`)
        // 기준으로 잡는다 — 타자 치는 동안 글이 늘어난다고 위치가 오르내리면 안 된다.
        let bodyHeight = min(bodyBox.clip, textHeight(fittedFull, width: messageRect.width, attributes: messageAttributes))
        let bodyTop = messageRect.midY + bodyHeight / 2
        // 재는 값과 그리는 결과가 어긋날 때가 있다 — boundingRect 는 해상도와 무관하게 재는데
        // 실제 글자는 화면 픽셀에 맞춰 스냅되면서 조금 넓어져, 잰 것보다 한 줄 더 접히곤 한다.
        // 그 한 줄이 둥근 말풍선의 아래 곡선에 걸려 반토막으로 그려졌다. 놓은 칸 밖은 잘라 둔다.
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: messageRect.minX, y: bodyTop - bodyHeight, width: messageRect.width, height: bodyHeight).clip()
        shownMessage.draw(
            // 글이 시작할 자리만 맞추면 되므로 위를 `bodyTop` 에 두고 높이는 넉넉히 준다.
            with: NSRect(x: messageRect.minX, y: bodyTop - messageRect.height, width: messageRect.width, height: messageRect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes,
            context: nil
        )
        NSGraphicsContext.restoreGraphicsState()

        // 동물의 숲의 "더 있어요" 삼각형. 접힌 상태에서 멘트가 잘렸을 때만 띄운다.
        if fittedFull.count < fullMessage.count {
            // 말풍선과 5pt 겹치게 올리고, 세 꼭짓점을 둥글린 삼각형으로 그린다.
            let caretWidth = 15 * scale
            let caretHeight = 8 * scale
            let caretRadius = 2.2 * scale
            let caretTop = ribbonRect.minY + 7 * scale
            let left = NSPoint(x: ribbonRect.midX - caretWidth / 2, y: caretTop)
            let right = NSPoint(x: ribbonRect.midX + caretWidth / 2, y: caretTop)
            let apex = NSPoint(x: ribbonRect.midX, y: caretTop - caretHeight)
            let caret = NSBezierPath()
            caret.move(to: NSPoint(x: (left.x + right.x) / 2, y: caretTop))
            caret.appendArc(from: right, to: apex, radius: caretRadius)
            caret.appendArc(from: apex, to: left, radius: caretRadius)
            caret.appendArc(from: left, to: right, radius: caretRadius)
            caret.close()
            NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.25, alpha: 0.97).setFill()
            caret.fill()
        }

    }

    /// 이름표에 들어갈 이름: 이 멘트가 나온 섹션. 자르기는 폭으로만 한다.
    private func sectionLabel() -> String {
        let title = (liveTitle ?? payload?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return payload?.project ?? "Claude Code" }
        return title
    }

    /// 말풍선 본문 글자 속성. 그리기와 "펼칠 필요가 있나" 판정이 같은 값을 봐야 한다.
    private func messageAttributes(scale: CGFloat, textDelta: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0.875 * scale
        return [
            .font: petFont(typeface, size: 18 * scale + textDelta),
            .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 0.94),
            .paragraphStyle: style
        ]
    }

    /// 말풍선 안에서 본문이 쓸 수 있는 칸.
    private func messageRect(in ribbonRect: NSRect, scale: CGFloat) -> NSRect {
        NSRect(
            x: ribbonRect.minX + 22 * scale,
            y: ribbonRect.minY + 14 * scale,
            width: ribbonRect.width - 44 * scale,
            height: max(0, (ribbonRect.maxY - 16 * scale) - (ribbonRect.minY + 14 * scale))
        )
    }

    /// 접힌 상태에서 문장이 이미 다 보이는지. 다 보이면 펼쳐도 새로 읽을 게 없다.
    private func bodyFitsCollapsed() -> Bool {
        let collapsed = petLayout(scale: petScale, width: bounds.width, expanded: false, chatScale: chatScale, fontSize: chatFontSize)
        let full = fullMessageText(for: animationCatalog[state] ?? animationCatalog[.idle]!)
        guard !full.isEmpty else { return true }
        let attributes = messageAttributes(scale: collapsed.chromeScale, textDelta: collapsed.textDelta)
        let rect = messageRect(in: collapsed.ribbonRect, scale: collapsed.chromeScale)
        let box = bodyLineBox(in: rect, attributes: attributes, scale: collapsed.chromeScale, textDelta: collapsed.textDelta)
        return (fittedBody(full, in: rect, attributes: attributes, maxHeight: box.fit) as String) == full
    }

    /// 말풍선에 들어갈 멘트 전체: Claude 가 마지막으로 한 말. 아직 없으면 레토가 하는 말로 대신한다.
    private func fullMessageText(for animation: Animation) -> String {
        let body = bodyText()
        return body.isEmpty ? animation.title : body
    }

    /// 화면에 들어가는 만큼 잘라낸 문장에서, 지금까지 찍힌 앞부분만 돌려준다.
    /// 부분 문자열을 매번 다시 잘라내면 두 줄을 넘는 순간 … 로 바뀌어 찍기가 멈춘 것처럼 보인다.
    /// 그래서 자르기는 먼저 한 번만 하고, 찍기는 그 결과 위에서만 진행한다.
    private func typedPortion(of fitted: String, fullLength: Int) -> String {
        guard typeTimer != nil, typedCount < fitted.count else { return fitted }
        return String(fitted.prefix(typedCount))
    }

    /// 멘트가 바뀌었으면 처음부터 다시 찍는다.
    private func restartTypingIfNeeded() {
        let full = fullMessageText(for: animationCatalog[state] ?? animationCatalog[.idle]!)
        guard full != typingSource else { return }
        typingSource = full
        typedCount = 0
        typeTimer?.invalidate()
        typeTimer = nil
        needsDisplay = true
        guard !full.isEmpty else { return }
        let timer = Timer(timeInterval: 0.018, repeats: true) { [weak self] _ in
            self?.advanceTyping()
        }
        typeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceTyping() {
        typedCount += 1
        if typedCount >= typingSource.count { finishTyping() }
        needsDisplay = true
    }

    private func finishTyping() {
        typedCount = typingSource.count
        typeTimer?.invalidate()
        typeTimer = nil
    }

    /// 이름표 한 줄에 들어갈 만큼만 남긴다.
    /// 뒤만 자르면 같은 프로젝트의 세션들이 전부 같은 이름표가 된다 —
    /// "백오피스 조직별 화면 목업…" 이 둘이면 어느 쪽인지 알 수 없다.
    /// 앞뒤를 남기고 가운데를 줄여 무엇에 관한 세션인지와 어떤 세션인지를 함께 보인다.
    /// 뒤가 앞보다 더 잘 갈라서(대개 앞은 프로젝트, 뒤는 하는 일) 뒤에 조금 더 준다.
    private func fittedSingleLine(_ text: String, maxWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSString {
        guard maxWidth > 0 else { return "" as NSString }
        func width(_ candidate: String) -> CGFloat {
            (candidate as NSString).size(withAttributes: attributes).width
        }
        if width(text) <= maxWidth { return text as NSString }

        let characters = Array(text)
        func candidate(_ head: Int, _ tail: Int) -> String {
            String(characters.prefix(head)) + "…" + String(characters.suffix(tail))
        }
        // 앞뒤를 번갈아 한 글자씩 늘린다. 한쪽만 먼저 채우면 반대쪽이 통째로 사라져
        // "…조직별 화면 목업 다시 봐줘" 처럼 무슨 프로젝트인지가 날아간다.
        // 같은 길이면 뒤를 먼저 준다 — 앞은 대개 프로젝트라 서로 같고, 뒤가 세션을 가른다.
        var head = 0
        var tail = 0
        while head + tail < characters.count {
            let growTailFirst = tail <= head
            let order = growTailFirst ? [(head, tail + 1), (head + 1, tail)] : [(head + 1, tail), (head, tail + 1)]
            var grew = false
            for (h, t) in order where h + t <= characters.count && width(candidate(h, t)) <= maxWidth {
                head = h
                tail = t
                grew = true
                break
            }
            if !grew { break }
        }
        // 가운데를 줄일 자리조차 없으면 예전처럼 뒤를 자른다.
        guard head + tail > 0 else {
            var trimmed = text
            while !trimmed.isEmpty, width(trimmed + "…") > maxWidth {
                trimmed = String(trimmed.dropLast())
            }
            return (trimmed.trimmingCharacters(in: .whitespaces) + "…") as NSString
        }
        let front = String(characters.prefix(head)).trimmingCharacters(in: .whitespaces)
        let back = String(characters.suffix(tail)).trimmingCharacters(in: .whitespaces)
        return (front + "…" + back) as NSString
    }

    /// 주어진 칸에 들어갈 만큼만 남기고 잘라낸다. 잘렸으면 끝에 … 를 붙인다.
    /// 말풍선에 몇 줄까지 넣어도 되는지. 사각 여백(`rect`)만 보면 안 된다 —
    /// 말풍선은 둥근 blob 이라 사각형 맨 아랫줄은 실제로 칠해지는 자리 밖이고, 거기 그린 글자는
    /// 아래 곡선에 걸려 반쯤 잘린다. 손글씨 기준으로 잡아 둔 줄 수(접으면 둘, 펼치면 넷)를
    /// 상한으로 삼아, 더 작은 글꼴로 바꿔도 한 줄이 더 비집고 들어가지 못하게 막는다.
    /// 두 값을 준다.
    ///   `fit`  — 글자를 깎을 때 쓰는 상한. 딱 N 줄 높이로 두면 재는 오차 때문에 N 줄이 안 들어가
    ///            한 줄로 떨어지는 일이 있어 3할쯤 여유를 준다. N+1 줄은 한 줄이 통째로 더 필요하니 못 들어온다.
    ///   `clip` — 실제로 그릴 때 남길 칸. 이건 정확히 N 줄이다.
    private func bodyLineBox(in rect: NSRect, attributes: [NSAttributedString.Key: Any], scale: CGFloat, textDelta: CGFloat) -> (clip: CGFloat, fit: CGFloat) {
        let spacing = 0.875 * scale
        func lineHeight(_ font: NSFont) -> CGFloat { font.ascender - font.descender + font.leading }
        let referenceLine = lineHeight(petFont(.handwriting, size: 18 * scale + textDelta))
        let lines = max(1, Int(((rect.height + spacing) / (referenceLine + spacing)).rounded(.down)))
        guard let font = attributes[.font] as? NSFont else { return (rect.height, rect.height) }
        let line = lineHeight(font)
        let exact = min(rect.height, line * CGFloat(lines) + spacing * CGFloat(lines - 1))
        return (exact, min(rect.height, exact + line * 0.3))
    }

    /// 주어진 폭에서 이 글이 차지하는 높이.
    private func textHeight(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height
    }

    private struct JeanneBodyFit {
        let input: NSAttributedString
        let width: CGFloat
        let maxHeight: CGFloat
        let result: NSString
    }
    private var jeanneBodyFits: [JeanneBodyFit] = []

    private func fittedBody(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any], maxHeight: CGFloat) -> NSString {
        let input = NSAttributedString(string: text, attributes: attributes)
        // 일부 스킨은 60fps 로 다시 그린다. 그때마다 글자 높이를 다시 측정하지 않게 모든 스킨에 캐시를 쓴다.
        if let cached = jeanneBodyFits.first(where: {
            $0.width == rect.width && $0.maxHeight == maxHeight && $0.input.isEqual(to: input)
        }) { return cached.result }
        let result = uncachedFittedBody(text, in: rect, attributes: attributes, maxHeight: maxHeight)
        if jeanneBodyFits.count >= 16 { jeanneBodyFits.removeFirst() }
        jeanneBodyFits.append(JeanneBodyFit(input: input, width: rect.width, maxHeight: maxHeight, result: result))
        return result
    }
    func validateJeanneBodyFitCache() -> Bool {
        let originalSkin = skin
        skin = .jeanne
        defer { skin = originalSkin }
        let long = String(repeating: "레토의 작업 결과와 다음 동작을 확인합니다. ", count: 30)
        let inputs: [(String, CGFloat, CGFloat, CGFloat)] = [
            (long, 150, 40, 12), (long, 150, 40, 12),
            ("새 메시지", 150, 40, 12), (long, 220, 40, 12),
            (long, 150, 80, 12), (long, 150, 40, 18)
        ]
        for (text, width, height, size) in inputs {
            let rect = NSRect(x:0,y:0,width:width,height:height)
            let attrs: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:size)]
            let actual = fittedBody(text,in:rect,attributes:attrs,maxHeight:height)
            let expected = uncachedFittedBody(text,in:rect,attributes:attrs,maxHeight:height)
            if actual != expected { return false }
        }
        return true
    }

    private func uncachedFittedBody(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any], maxHeight: CGFloat) -> NSString {
        let box = NSSize(width: rect.width, height: .greatestFiniteMagnitude)
        func height(_ candidate: String) -> CGFloat {
            (candidate as NSString).boundingRect(
                with: box,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height
        }
        if height(text) <= maxHeight { return text as NSString }
        var trimmed = text
        while !trimmed.isEmpty, height(trimmed + "…") > maxHeight {
            trimmed = String(trimmed.dropLast(6))
        }
        return (trimmed.trimmingCharacters(in: .whitespaces) + "…") as NSString
    }

    /// 말풍선을 펼쳤을 때 읽을 본문. 훅이 담아 둔 마지막 답(180자)에서 마크다운 기호를 걷어낸다.
    /// 머리 위로 떠오르는 z. 자는 티는 그림만으로는 약하고, 졸 때는 말풍선을 건드리지 않기로
    /// 했으니 여기서 말해 준다. 프레임을 따라 세 글자가 차례로 커지고 옅어지며 올라간다.
    private func drawSleepBreath(petRect: NSRect, scale: CGFloat) {
        guard let animation = animationCatalog[.sleeping] else { return }
        let cycle = CGFloat(frameIndex) / CGFloat(max(1, animation.frames))
        // 귀 오른쪽 위에서 시작해 비스듬히 올라간다.
        let origin = NSPoint(x: petRect.midX + petRect.width * 0.20, y: petRect.maxY - petRect.height * 0.30)
        for index in 0..<3 {
            // 글자마다 한 박자씩 늦게 떠오른다.
            let phase = (cycle + CGFloat(index) / 3).truncatingRemainder(dividingBy: 1)
            let rise = phase * 26 * scale
            let size = (10 + 6 * CGFloat(index)) * scale
            // 떠오르다 사라진다. 갓 나온 것과 사라지는 것 모두 옅게.
            let fade = sin(phase * .pi)
            guard fade > 0.05 else { continue }
            // 어두운 회색 하나로 그리면 어두운 배경화면에서 통째로 사라진다. 자는 상태는 말풍선을
            // 건드리지 않기로 했으니 이 z 가 유일한 신호인데, 그게 배경에 따라 없어지면 안 된다.
            // 말풍선과 같은 크림색으로 칠하고 어두운 테두리를 둘러 양쪽 배경에서 다 읽히게 한다.
            // strokeWidth 가 음수면 채우기와 테두리를 함께 그린다.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: petFont(typeface, size: size, bold: true),
                .foregroundColor: hexColor(0xFFFBE8).withAlphaComponent(0.92 * fade),
                .strokeColor: NSColor(calibratedWhite: 0.22, alpha: 0.70 * fade),
                .strokeWidth: -3.0
            ]
            let text = "z" as NSString
            text.draw(
                at: NSPoint(x: origin.x + rise * 0.45 + CGFloat(index) * 3 * scale, y: origin.y + rise),
                withAttributes: attributes
            )
        }
    }

    /// 발밑에 깔리는 타원 그림자. 가운데가 진하고 바깥으로 사라지는 방사 그라디언트라
    /// 테두리가 생기지 않는다. 몸 위쪽으로는 아무것도 번지지 않는다.
    private func drawGroundShadow(petRect: NSRect, scale: CGFloat) {
        let width = petRect.width * 0.42
        let height = width * 0.20
        let rect = NSRect(
            x: petRect.midX - width / 2,
            y: petRect.minY + 8 * scale - height / 2,
            width: width,
            height: height
        )
        guard let gradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.20),
            NSColor.black.withAlphaComponent(0.0)
        ]) else { return }
        gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
    }

    private func bodyText() -> String {
        // 앱이 트랜스크립트에서 방금 집어 온 문장이 있으면 그게 가장 최신이다.
        let source = liveMessage ?? payload?.lastAssistantMessage
        guard let raw = source, !raw.isEmpty else { return "" }
        var text = raw
        for token in ["**", "```", "`", "##", "#", "|", ">", "- ", "* "] {
            text = text.replacingOccurrences(of: token, with: " ")
        }
        // 링크가 날것으로 들어오면 두 줄을 다 잡아먹는다. 도메인만 남긴다.
        let words = text.split(whereSeparator: { $0.isWhitespace }).map { word -> Substring in
            guard word.hasPrefix("http://") || word.hasPrefix("https://"),
                  let host = URL(string: String(word))?.host else { return word }
            return Substring(host)
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detailText(for animation: Animation) -> String {
        if payload?.source == "slack" { return state == .idle ? "Slack" : "Slack · 새 메시지" }
        if (state == .review || state == .running), let tool = payload?.toolName, !tool.isEmpty { return "\(animation.kicker) · \(tool.uppercased())" }
        if state == .failed, let error = payload?.error, !error.isEmpty { return "\(animation.kicker) · \(String(error.prefix(24)).uppercased())" }
        return animation.kicker
    }
}

final class StateMonitor {
    private let registryURL: URL
    private let fallbackStateURL: URL
    private var timer: Timer?
    private var lastData: Data?
    private var lastSessions: [StatePayload] = []
    private var lastTranscriptStamps: [String: Double] = [:]
    private var lastCodexIndexStamp: Double?
    /// 훅이 꺼진 Codex task도 롤아웃 파일은 계속 자란다. 인덱스만 보면 같은 task 안의
    /// 새 요청·완료를 놓치므로, 낮은 빈도로 목록을 다시 만들 기회를 준다.
    private var lastCodexRolloutRefresh = Date.distantPast
    private let onChange: ([StatePayload]) -> Void

    init(registryURL: URL, fallbackStateURL: URL, onChange: @escaping ([StatePayload]) -> Void) {
        self.registryURL = registryURL
        self.fallbackStateURL = fallbackStateURL
        self.onChange = onChange
    }

    func start() {
        poll()
        let pollingTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        timer = pollingTimer
        RunLoop.main.add(pollingTimer, forMode: .common)
    }

    /// 타이머는 `.common` 모드라 알림창이 떠 있는 동안에도 계속 돈다. 평소에는 그게 맞지만,
    /// 제거처럼 상태를 걷어내는 중에는 멈춰야 방금 지운 것이 폴링 때문에 되살아나지 않는다.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let data: Data
        let isRegistry: Bool
        if let registryData = try? Data(contentsOf: registryURL) {
            data = registryData
            isRegistry = true
        } else if let fallbackData = try? Data(contentsOf: fallbackStateURL) {
            data = fallbackData
            isRegistry = false
        } else {
            // 상태 파일이 사라졌다. 예전에는 그냥 돌아가서 마지막 화면이 영원히 굳었다 —
            // 지워진 세션이 계속 일하는 것처럼 보였다. 빈 목록을 넘겨 조용한 상태로 내려앉힌다.
            if lastData != nil {
                lastData = nil
                onChange([])
            }
            let codexIndexStamp = codexThreadIndexStamp()
            let needsCodexRefresh = Date().timeIntervalSince(lastCodexRolloutRefresh) >= 3
            if codexIndexStamp != lastCodexIndexStamp || needsCodexRefresh {
                lastCodexIndexStamp = codexIndexStamp
                lastCodexRolloutRefresh = Date()
                onChange([])
            }
            return
        }
        if data == lastData {
            let stamps = transcriptStamps(in: lastSessions)
            let codexIndexStamp = codexThreadIndexStamp()
            let needsCodexRefresh = Date().timeIntervalSince(lastCodexRolloutRefresh) >= 3
            guard stamps != lastTranscriptStamps || codexIndexStamp != lastCodexIndexStamp || needsCodexRefresh else { return }
            lastTranscriptStamps = stamps
            lastCodexIndexStamp = codexIndexStamp
            lastCodexRolloutRefresh = Date()
            onChange(lastSessions)
            return
        }

        // 훅은 임시 파일에 쓴 뒤 rename 하므로 반쪽 파일이 보일 일은 없다. 그래도 읽지 못한
        // 내용을 기억해 두지는 않는다 — 기억하면 같은 내용이 다시 와도 건너뛰어 굳는다.
        if isRegistry, let registry = try? JSONDecoder().decode(SessionRegistry.self, from: data) {
            lastData = data
            lastSessions = Array(registry.sessions.values)
            lastTranscriptStamps = transcriptStamps(in: lastSessions)
            lastCodexIndexStamp = codexThreadIndexStamp()
            lastCodexRolloutRefresh = Date()
            onChange(lastSessions)
        } else if let payload = try? JSONDecoder().decode(StatePayload.self, from: data) {
            lastData = data
            lastSessions = [payload]
            lastTranscriptStamps = transcriptStamps(in: lastSessions)
            lastCodexIndexStamp = codexThreadIndexStamp()
            lastCodexRolloutRefresh = Date()
            onChange(lastSessions)
        }
    }

    private func transcriptStamps(in sessions: [StatePayload]) -> [String: Double] {
        var stamps: [String: Double] = [:]
        for payload in sessions {
            guard let path = payload.transcriptPath,
                  let modified = transcriptModifiedAtMs(path: path) else { continue }
            stamps[path] = max(stamps[path] ?? 0, modified)
        }
        return stamps
    }

    private func codexThreadIndexStamp() -> Double? {
        let index = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl").path
        return transcriptModifiedAtMs(path: index)
    }
}

extension RettoView {
    func validateClassicGrownTransitions() -> Bool {
        func applyState(_ value: PetState, sleep: Bool = false) {
            let payload = try! JSONDecoder().decode(StatePayload.self,
                from: Data("{\"state\":\"\(value.rawValue)\",\"sessionId\":\"classic-grown-test\",\"projectName\":\"Retto\"}".utf8))
            apply(payload,state:value,sleepPose:sleep,sessionCount:1,attentionCount:0,isPinned:false)
        }
        for value in PetState.allCases {
            applyState(value)
            guard let a = currentAnimation, let m = ClassicGrown.motion(row:a.row),
                  a.frames == m.files.count, frameIndex == 0 else { print("Classic transition state failed: \(value)"); return false }
        }
        applyState(.idle)
        for direction in [DragRun.right,.left] {
            setDragRunForPreview(direction)
            guard let a=currentAnimation,a.frames==16,abs(a.interval-0.1)<0.000001 else { print("Classic transition check failed at line \(#line)"); return false }
        }
        setDragRunForPreview(nil)
        playReaction()
        classicGrownEpoch = ProcessInfo.processInfo.systemUptime - 2.401
        advanceFrame()
        guard transientState == nil,visibleState == .idle else { print("Classic transition check failed at line \(#line)"); return false }
        applyState(.waving)
        classicGrownEpoch = ProcessInfo.processInfo.systemUptime - 4.801
        advanceFrame()
        guard visibleState == .idle,state == .waving else { print("Classic transition check failed at line \(#line)"); return false }
        applyState(.idle,sleep:true)
        guard visibleState == .sleeping,currentAnimation?.row == 11 else { print("Classic transition check failed at line \(#line)"); return false }
        applyState(.idle,sleep:false)
        guard visibleState == .idle,currentAnimation?.frames == 9 else { print("Classic transition check failed at line \(#line)"); return false }
        animationTimer?.invalidate()
        return true
    }
}

// Included in PetView.swift so production-private state and cursor handling are exercised directly.
extension RettoView {
    func validateClassicGazeTransitions() -> Bool {
        func applyGazeState(_ value: PetState, sleep: Bool = false) {
            let payload=try! JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"\(value.rawValue)\",\"sessionId\":\"classic-gaze-check\",\"projectName\":\"Retto\"}".utf8))
            apply(payload,state:value,sleepPose:sleep,sessionCount:1,attentionCount:0,isPinned:false)
        }
        guard ClassicGrown.gazeSelfTest() else { return false }
        for value in [PetState.idle,.running,.waving] {
            applyGazeState(value)
            for direction in 0..<16 {
                clearGaze()
                let angle=Double(direction)*Double.pi/8
                updateHover(at:NSPoint(x:layout.petRect.midX+300*sin(angle),y:layout.petRect.midY+300*cos(angle)))
                guard lookDirection==direction,gazeTargetDirection==direction else { print("Classic gaze mapping failed: \(value) \(direction)");return false }
                let row=direction<8 ? 9:10
                guard ClassicGrown.image(row:row,frame:direction%8) != nil else{return false}
            }
            clearGaze()
            guard lookDirection==nil,frameIndex==0,currentAnimation?.row==animationCatalog[value]?.row else{return false}
            // Exercise the real reset timer and verify the pose clock restarts on return.
            updateHover(at:NSPoint(x:layout.petRect.maxX+300,y:layout.petRect.midY))
            guard lookDirection != nil else{return false}
            RunLoop.main.run(until:Date(timeIntervalSinceNow:gazeHoldDuration+0.10))
            guard lookDirection==nil,ProcessInfo.processInfo.systemUptime-classicGrownEpoch<0.30 else{print("Classic reset failed: \(value)");return false}
        }
        applyGazeState(.idle)
        lookDirection=15
        updateGaze(toward:0)
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.09))
        guard lookDirection==0 else{print("Classic short wrap failed");return false}
        clearGaze()
        for value in [PetState.review,.waiting,.failed] {
            applyGazeState(value)
            updateHover(at:NSPoint(x:layout.petRect.maxX+300,y:layout.petRect.midY))
            guard lookDirection==nil else{print("Classic gaze state gate failed");return false}
        }
        applyGazeState(.idle,sleep:true)
        updateHover(at:NSPoint(x:layout.petRect.maxX+300,y:layout.petRect.midY))
        guard lookDirection==nil,currentAnimation?.row==11 else{return false}
        applyGazeState(.idle,sleep:false)
        for direction in [DragRun.right,.left] {
            setDragRunForPreview(direction)
            updateHover(at:NSPoint(x:layout.petRect.maxX+300,y:layout.petRect.midY))
            guard lookDirection==nil else{return false}
        }
        setDragRunForPreview(nil)
        playReaction()
        updateHover(at:NSPoint(x:layout.petRect.maxX+300,y:layout.petRect.midY))
        guard transientState == .jumping,lookDirection==nil else{return false}
        classicGrownEpoch=ProcessInfo.processInfo.systemUptime-2.401
        advanceFrame()
        guard transientState==nil,currentAnimation?.row==0 else{return false}
        animationTimer?.invalidate();gazeResetTimer?.invalidate();gazeTransitionTimer?.invalidate()
        print("Classic gaze:48 cursor/state mappings,0.8s return,15-to0 wrap,sleep/drag/reaction gates passed")
        return true
    }
}
