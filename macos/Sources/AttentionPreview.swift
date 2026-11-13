import AppKit

/// README · 검수용 한 장. `--attention-state` 외에 `--attention-title` · `--attention-message` · `--attention-skin` ·
/// `--attention-time`(초, 그 순간의 자세)을 받는다. 없으면 예전 검증 문구 그대로다.
func renderAttentionPreview(to path: String) -> Int32 {
    _ = registerRettoFont()
    func option(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.count > index + 1 else { return nil }
        return CommandLine.arguments[index + 1]
    }
    let skin = option("--attention-skin").flatMap(PetSkin.init(rawValue:)) ?? .classic
    guard let image = previewSheet(skin) else { return 1 }
    var state: PetState = .waiting
    if let value = option("--attention-state") { state = PetState(rawValue: value) ?? .waiting }
    let count = needsInputStates.contains(state) ? 1 : 0
    let title = option("--attention-title") ?? "상태 표시 검증"
    let object: [String: Any] = ["state": state.rawValue, "source": "codex", "sessionId": "preview", "sessionTitle": title, "attention": count > 0]
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let payload = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
    let size = petLayout(scale: 1).windowSize
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image, skin: skin, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    let time = option("--attention-time").flatMap(Double.init)
    if time != nil { view.exportClock = 1000; view.exportResetEpochs() }
    let message = option("--attention-message") ?? (state == .waiting ? "파일 첨부 승인을 기다리고 있어요." : state == .failed ? "작업이 실패했어요. 내용을 확인해 주세요." : "작업을 진행하고 있어요.")
    view.apply(payload, liveMessage: message, sessionCount: 1,
               attentionCount: count, attentionState: state, attentionSource: "codex", inputCount: state == .waiting ? 1 : 0,
               connectionStatus: nil, isPinned: false)
    view.settleAnimations()
    if let time { view.exportRestart(); view.exportAdvance(to: 1000 + time) }
    guard state != .waiting || view.accessibilityLabel()?.contains("입력 필요 1개") == true else { return 1 }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep) else { return 1 }
    rep.size = size
    context.cgContext.scaleBy(x: 2, y: 2)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    NSColor.white.setFill(); view.bounds.fill(); view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
    do { try data.write(to: URL(fileURLWithPath: path)); print("Attention rendering and accessibility: PASS"); return 0 }
    catch { return 1 }
}

private func previewSheet(_ skin: PetSkin) -> NSImage? {
    if skin == .amuRan { return NSImage(size: NSSize(width: 7168, height: 7680)) }
    if skin == .hachupingping { return HachupingSkin.placeholder }
    if skin == .howl { return HowlSkin.placeholder }
    if skin == .jeanne { return JeanneSkin.placeholder }
    if skin == .pichiPitch { return PichiSkin.placeholder }
    if skin == .chocolatHeart { return ChocolatHeart.placeholder }
    if skin == .hana { return HanaFrameCache.placeholder }
    guard let url = Bundle.main.url(forResource: skin.resourceName, withExtension: "webp") else { return nil }
    return NSImage(contentsOf: url)
}
