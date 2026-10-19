import AppKit
import Foundation

enum JeanneSkin {
    struct State: Decodable { let id: String; let row: Int; let cycle: Double; let times: [Double]; let files: [String] }
    struct Manifest: Decodable { let states: [State] }
    static let manifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "JeanneFrames"), let data = try? Data(contentsOf: url) else { return nil }
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
        return Double(cycles) * s.cycle + s.times.prefix(frame).reduce(0,+)
    }
    static func position(row: Int, time: Double) -> (frame: Int, cycles: Int) {
        guard let s = state(row: row) else { return (0,0) }
        let t = max(0,time), cycles = Int(t / s.cycle); var q = t.truncatingRemainder(dividingBy: s.cycle)
        for (i,d) in s.times.enumerated() { if q < d { return (i,cycles) }; q -= d }
        return (s.files.count-1,cycles)
    }
    static func animation(_ a: Animation) -> Animation {
        guard let s = state(row: a.row) else { return a }
        return Animation(row: a.row, frames: s.files.count, interval: s.cycle / Double(s.files.count), cycleLimit: a.cycleLimit, kicker: a.kicker, title: a.title, tone: a.tone)
    }
    static func image(_ f: String) -> NSImage? {
        if let im = cache.object(forKey: f as NSString) { return im }
        guard let url = Bundle.main.url(forResource: f, withExtension: nil, subdirectory: "JeanneFrames"), let im = NSImage(contentsOf: url) else { return nil }
        cache.setObject(im, forKey: f as NSString); return im
    }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) {
        let file: String
        if row == 9 || row == 10 { file = "gaze-\((row-9)*8+frame).png" }
        else { guard let s = state(row: row) else { return }; file = s.files[frame % s.files.count] }
        image(file)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }
    static func validate() -> Bool {
        guard let m = manifest, m.states.count == 10 else { print("Jeanne validation failure at line \(#line)"); return false }
        for s in m.states {
            let expected = (s.row == 1 || s.row == 2) ? 8 : 16
            guard s.files.count == expected, s.times.count == expected, abs(s.times.reduce(0,+)-s.cycle)<0.000001 else { print("Jeanne validation failure at line \(#line)"); return false }
            var elapsed = 0.0
            for (i,f) in s.files.enumerated() {
                guard image(f)?.size == NSSize(width:448,height:640), position(row:s.row,time:elapsed+0.00001).frame == i else { print("Jeanne validation failure at line \(#line)"); return false }
                elapsed += s.times[i]
            }
            guard position(row:s.row,time:s.cycle+0.00001).cycles == 1 else { print("Jeanne validation failure at line \(#line)"); return false }
        }
        for i in 0..<16 { guard image("gaze-\(i).png")?.size == NSSize(width:448,height:640) else { print("Jeanne validation failure at line \(#line)"); return false } }
        print("{\"jeanneOK\":true,\"cells\":144,\"gaze\":16,\"timing\":\"v31\"}")
        return true
    }

}

func renderJeannePreview(to path: String) -> Int32 {
    registerRettoFont()
    let states: [(PetState, DragRun?)] = PetState.allCases.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    let layout = petLayout(scale: 224 / basePetWidth)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2240, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    for (i, pair) in states.enumerated() {
        let v = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: JeanneSkin.placeholder, skin: .jeanne, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        v.petScale = 224 / basePetWidth
        let data = "{\"state\":\"\(pair.0.rawValue)\",\"sessionId\":\"jeanne-fixture\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let p = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
        v.apply(p, sessionCount: 1, attentionCount: 0, isPinned: false); if let drag = pair.1 { v.setDragRunForPreview(drag) }
        v.settleAnimations(); v.setJeanneTimeForPreview(1.6)
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
