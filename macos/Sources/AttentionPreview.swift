import AppKit

func renderAttentionPreview(to path: String) -> Int32 {
    _ = registerRettoFont()
    guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"), let image = NSImage(contentsOf: url) else { return 1 }
    let data = Data("{\"state\":\"waiting\",\"source\":\"codex\",\"sessionId\":\"preview\",\"sessionTitle\":\"입력 대기 표시 확인\",\"attention\":true}".utf8)
    guard let payload = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
    let size = petLayout(scale: 1).windowSize
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    view.apply(payload, liveMessage: "선택할 항목을 확인하고 답변해 주세요. 답변할 때까지 이 작업을 표시해요.", sessionCount: 5,
               attentionCount: 3, attentionState: .waiting, attentionSource: "codex", inputCount: 3,
               connectionStatus: "Slack 재연결 중 · 새 메시지 지연 가능", isPinned: true)
    view.settleAnimations()
    guard view.accessibilityLabel()?.contains("입력 필요 3개") == true,
          view.accessibilityLabel()?.contains("Slack 재연결") == true else { return 1 }
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
