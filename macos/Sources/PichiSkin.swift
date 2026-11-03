import AppKit
import Foundation

enum PichiSkin {
    /// Release decoded frames when the single overlay switches away from this skin.
    static func removeCachedImages() {
        cache.removeAllObjects()
    }

    struct Cell: Decodable { let file: String; let duration_ms: Double }
    struct Resource: Decodable { let file: String }
    struct Effect: Decodable { let back: Resource; let front: Resource }
    struct State: Decodable { let id: String; let row: Int; let cycle_ms: Double; let cells: [Cell]; let effect_interval_ms: Double; let effects: [Effect] }
    struct Manifest: Decodable { let states: [State] }
    static let manifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "PichiFrames"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 192; c.totalCostLimit = 64 * 1024 * 1024; return c
    }()
    static var available: Bool { manifest?.states.count == 10 }
    static var placeholder: NSImage { NSImage(size: NSSize(width: 7168, height: 7680)) }
    static func state(row: Int) -> State? { manifest?.states.first { $0.row == row } }
    static func elapsed(row: Int, frame: Int, cycles: Int) -> Double {
        guard let s = state(row: row) else { return 0 }
        return (Double(cycles) * s.cycle_ms + s.cells.prefix(frame).reduce(0) { $0 + $1.duration_ms }) / 1000
    }
    static func position(row: Int, time: Double) -> (frame: Int, cycles: Int) {
        guard let s = state(row: row) else { return (0, 0) }
        let ms = max(0, time * 1000), cycles = Int(ms / s.cycle_ms), phase = ms.truncatingRemainder(dividingBy: s.cycle_ms)
        var end = 0.0
        for (i, c) in s.cells.enumerated() { end += c.duration_ms; if phase < end { return (i, cycles) } }
        return (s.cells.count - 1, cycles)
    }
    static func animation(_ a: Animation) -> Animation {
        guard let s = state(row: a.row) else { return a }
        return Animation(row: a.row, frames: s.cells.count, interval: s.cycle_ms / Double(s.cells.count) / 1000, cycleLimit: a.cycleLimit, kicker: a.kicker, title: a.title, tone: a.tone)
    }
    static func image(_ file: String) -> NSImage? {
        if let i = cache.object(forKey: file as NSString) { return i }
        guard let resources = Bundle.main.resourceURL, let i = NSImage(contentsOf: resources.appendingPathComponent("PichiFrames").appendingPathComponent(file)) else { return nil }
        guard let rep = i.representations.first, rep.pixelsWide == 224, rep.pixelsHigh == 320 else { return nil }
        i.size = NSSize(width: 224, height: 320)
        cache.setObject(i, forKey: file as NSString, cost: Int(i.size.width * i.size.height) * 4); return i
    }
    static func draw(_ image: NSImage?, in rect: NSRect) {
        guard let image else { return }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) {
        guard let s = state(row: row), s.cells.indices.contains(frame) else { return }
        draw(image(s.cells[frame].file), in: rect)
    }
    static func drawEffects(row: Int, time: Double, front: Bool, in rect: NSRect) {
        guard let s = state(row: row), !s.effects.isEmpty else { return }
        let phase = max(0, time * 1000).truncatingRemainder(dividingBy: s.cycle_ms)
        let i = min(s.effects.count - 1, Int(phase / s.effect_interval_ms))
        draw(image(front ? s.effects[i].front.file : s.effects[i].back.file), in: rect)
    }
    static func validate() -> Bool {
        guard let m = manifest, m.states.count == 10 else { print("pichi: manifest unavailable"); return false }
        for s in m.states {
            guard abs(s.cells.reduce(0) { $0 + $1.duration_ms } - s.cycle_ms) < 0.01,
                  abs(Double(s.effects.count) * s.effect_interval_ms - s.cycle_ms) < 0.01 else { print("pichi: timing mismatch \(s.id)"); return false }
            for c in s.cells { guard let i = image(c.file), i.size == NSSize(width: 224, height: 320) else { print("pichi: invalid character \(c.file) \(String(describing: image(c.file)?.size))"); return false } }
            for e in s.effects { for f in [e.back.file, e.front.file] { guard let i = image(f), i.size == NSSize(width: 224, height: 320) else { print("pichi: invalid effect \(f) \(String(describing: image(f)?.size))"); return false } } }
            guard position(row: s.row, time: s.cycle_ms / 1000 + 0.001).cycles == 1 else { return false }
        }
        func snapshot(_ t: Double) -> Data? {
            let im = NSImage(size: NSSize(width: 224, height: 320)); im.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 224, height: 320).fill()
            let r = NSRect(x: 0, y: 0, width: 224, height: 320)
            drawEffects(row: 3, time: t, front: false, in: r); drawCharacter(row: 3, frame: 0, in: r); drawEffects(row: 3, time: t, front: true, in: r)
            im.unlockFocus(); return im.tiffRepresentation
        }
        return snapshot(0.15) != snapshot(0.85)
    }
}

func renderPichiPreview(to path: String) -> Int32 {
    registerRettoFont()
    let states: [(PetState, DragRun?)] = PetState.allCases.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    let layout = petLayout(scale: 224 / basePetWidth)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2240, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    for (i, pair) in states.enumerated() {
        let v = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: PichiSkin.placeholder, skin: .pichiPitch, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        v.petScale = 224 / basePetWidth
        let data = "{\"state\":\"\(pair.0.rawValue)\",\"sessionId\":\"pichi-fixture\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let p = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
        v.apply(p, sessionCount: 1, attentionCount: 0, isPinned: false); if let drag = pair.1 { v.setDragRunForPreview(drag) }
        v.settleAnimations(); v.setPichiTimeForPreview(1.6)
        for dark in 0..<2 {
            let x = CGFloat(i * 224), y = CGFloat((1 - dark) * 320)
            (dark == 0 ? NSColor.white : NSColor(calibratedWhite: 0.14, alpha: 1)).setFill(); NSRect(x: x, y: y, width: 224, height: 320).fill()
            NSGraphicsContext.saveGraphicsState(); NSRect(x: x, y: y, width: 224, height: 320).clip()
            let a = NSAffineTransform(); a.translateX(by: x - layout.petRect.minX, yBy: y - layout.petRect.minY); a.concat(); v.draw(v.bounds); NSGraphicsContext.restoreGraphicsState()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return 1 }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { return 1 }; return 0
}
