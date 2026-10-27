import AppKit

func renderAttentionPreview(to path: String) -> Int32 {
    _ = registerRettoFont()
    guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"), let image = NSImage(contentsOf: url) else { return 1 }
    var state: PetState = .waiting
    if let flag = CommandLine.arguments.firstIndex(of: "--attention-state"), CommandLine.arguments.count > flag + 1 {
        state = PetState(rawValue: CommandLine.arguments[flag + 1]) ?? .waiting
    }
    let count = needsInputStates.contains(state) ? 1 : 0
    let data = Data("{\"state\":\"\(state.rawValue)\",\"source\":\"codex\",\"sessionId\":\"preview\",\"sessionTitle\":\"상태 표시 검증\",\"attention\":\(count > 0)}".utf8)
    guard let payload = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
    let size = petLayout(scale: 1).windowSize
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    let message = state == .waiting ? "파일 첨부 승인을 기다리고 있어요." : state == .failed ? "작업이 실패했어요. 내용을 확인해 주세요." : "작업을 진행하고 있어요."
    view.apply(payload, liveMessage: message, sessionCount: 1,
               attentionCount: count, attentionState: state, attentionSource: "codex", inputCount: state == .waiting ? 1 : 0,
               connectionStatus: nil, isPinned: false)
    view.settleAnimations()
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
