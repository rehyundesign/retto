import AppKit
import Foundation

enum HanaMotion {
    static let playbackSpeed = 0.5
    static let durations: [Int: Double] = [0: 1.6, 1: 0.8, 2: 0.8, 3: 1.2, 4: 1.2,
                                         5: 1.6, 6: 1.6, 7: 1.2, 8: 1.6, 11: 3.2]
    static func animation(_ original: Animation) -> Animation {
        Animation(row: original.row, frames: 16,
                  interval: (durations[original.row] ?? 2) / (16 * playbackSpeed),
                  cycleLimit: original.cycleLimit, kicker: original.kicker,
                  title: original.title, tone: original.tone)
    }
    static func effectFrame(time: TimeInterval) -> Int {
        let scaledTime = time * playbackSpeed
        let phase = (scaledTime.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4)
        return min(79, Int(phase * 20))
    }
    static func position(elapsed: TimeInterval, interval: TimeInterval, frames: Int = 16) -> (frame: Int, cycles: Int) {
        let tick = Int(max(0, elapsed) / interval)
        return (tick % frames, tick / frames)
    }
    static func id(state: PetState, drag: DragRun?) -> String {
        if let drag { return drag == .right ? "drag-right" : "drag-left" }
        return state.rawValue
    }
}

/// 작은 프레임만 읽고, 캐릭터와 효과 캐시의 메모리 사용량을 제한한다.
enum HanaFrameCache {
    private static let characters: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48; cache.totalCostLimit = 56 * 1024 * 1024
        return cache
    }()
    private static let effects: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 192; cache.totalCostLimit = 56 * 1024 * 1024
        return cache
    }()
    static func image(_ name: String, character: Bool = false) -> NSImage? {
        let cache = character ? characters : effects
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "HanaFrames"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: name as NSString,
                        cost: Int(image.size.width * image.size.height) * 4)
        return image
    }
    static var placeholder: NSImage { NSImage(size: NSSize(width: 7168, height: 7680)) }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) -> Bool {
        guard let image = image("character-\(row)-\(frame)", character: true) else { return false }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        return true
    }
}

/// 20fps 효과의 시간은 캐릭터 프레임과 별도로 진행한다.
final class HanaEffectLayers {
    func draw(state: PetState, drag: DragRun?, in rect: NSRect, time: TimeInterval, front isFront: Bool) {
        let id = HanaMotion.id(state: state, drag: drag)
        let frame = HanaMotion.effectFrame(time: time)
        let layer = isFront ? "front" : "back"
        guard let image = HanaFrameCache.image("\(id)-\(layer)-\(frame)") else { return }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }
}

func hanaSkinSelfTest() -> Bool {
    guard let url = Bundle.main.url(forResource: PetSkin.hana.resourceName, withExtension: "webp"),
          let sheet = NSImage(contentsOf: url), SpriteSheetLayout.forImage(size: sheet.size) == .retto16 else { print("hana: character layout missing"); return false }
    let ids = PetState.allCases.map(\.rawValue) + ["drag-right", "drag-left"]
    for id in ids {
        for layer in ["back", "front"] {
            // 휴식의 뒤 레이어는 완전히 투명하여 AppKit이 이미지를 만들지 않는다.
            if id == "idle", layer == "back" { continue }
            guard let url = Bundle.main.url(forResource: "hana-\(id)-effects-\(layer)", withExtension: "webp"),
                  let image = NSImage(contentsOf: url), image.size == NSSize(width: 3584, height: 1600) else { print("hana: effect resource invalid \(id) \(layer)"); return false }
        }
    }
    for row in HanaMotion.durations.keys {
        for frame in 0..<16 {
            guard Bundle.main.url(forResource: "character-\(row)-\(frame)", withExtension: "png", subdirectory: "HanaFrames") != nil else { return false }
        }
    }
    for id in ids { for layer in ["back", "front"] { for frame in 0..<80 {
        guard Bundle.main.url(forResource: "\(id)-\(layer)-\(frame)", withExtension: "png", subdirectory: "HanaFrames") != nil else { return false }
    } } }
    let delayed = HanaMotion.position(elapsed: 0.51, interval: 0.1)
    let nextCycle = HanaMotion.position(elapsed: 1.69, interval: 0.1)
    guard delayed.frame == 5, delayed.cycles == 0,
          nextCycle.frame == 0, nextCycle.cycles == 1 else { return false }
    guard HanaMotion.effectFrame(time: 0.13) != HanaMotion.effectFrame(time: 0.83),
          HanaMotion.effectFrame(time: 0.13) == HanaMotion.effectFrame(time: 8.13),
          animationCatalog.values.allSatisfy({ HanaMotion.animation($0).frames == 16 }) else { print("hana: frame clock invalid"); return false }
    // 같은 자세에서도 네이티브 앞/뒤 효과 픽셀이 시간에 따라 바뀌어야 한다.
    let layers = HanaEffectLayers()
    func snapshot(_ time: Double) -> Data? {
        let image = NSImage(size: NSSize(width: 224, height: 320))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 224, height: 320).fill()
        layers.draw(state: .running, drag: nil, in: NSRect(x: 0, y: 0, width: 224, height: 320), time: time, front: false)
        layers.draw(state: .running, drag: nil, in: NSRect(x: 0, y: 0, width: 224, height: 320), time: time, front: true)
        image.unlockFocus()
        return image.tiffRepresentation
    }
    guard let a = snapshot(0.13), let b = snapshot(0.83) else { return false }
    if a == b { print("hana: effect render unchanged") }; return a != b
}

func renderHanaMotionPreview(to path: String) -> Int32 {
    registerRettoFont()
    let sheet = HanaFrameCache.placeholder
    let states: [(PetState, DragRun?)] = PetState.allCases.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    let scale: CGFloat = 224 / basePetWidth
    let layout = petLayout(scale: scale)
    let size = NSSize(width: 16 * 224, height: states.count * 2 * 320)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    for (i, entry) in states.enumerated() {
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: sheet, skin: .hana, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        view.petScale = scale
        let fixture = "{\"state\":\"\(entry.0.rawValue)\",\"sessionId\":\"hana-preview\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { return 1 }
        view.apply(payload, sessionCount: 1, attentionCount: 0, isPinned: false)
        if let drag = entry.1 { view.setDragRunForPreview(drag) }
        view.settleAnimations()
        for dark in 0..<2 {
            for frame in 0..<16 {
                let x = CGFloat(frame * 224), y = size.height - CGFloat((i * 2 + dark + 1) * 320)
                (dark == 0 ? NSColor.white : NSColor(calibratedWhite: 0.14, alpha: 1)).setFill()
                NSRect(x: x, y: y, width: 224, height: 320).fill()
                view.setFrameForPreview(frame)
                view.setChristmasTimeForPreview(Double(frame) / 4)
                NSGraphicsContext.saveGraphicsState()
                NSRect(x: x, y: y, width: 224, height: 320).clip()
                let transform = NSAffineTransform()
                transform.translateX(by: x - layout.petRect.minX, yBy: y - layout.petRect.minY)
                transform.concat(); view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return 1 }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    return 0
}
