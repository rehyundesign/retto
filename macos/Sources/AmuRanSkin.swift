import AppKit
import Foundation

enum AmuRanMotion {
    static let cycles: [Int: Double] = [0:3.2, 1:1.6, 2:1.6, 3:2.4, 4:2.4, 5:3.2, 6:3.2, 7:2.4, 8:3.2, 11:6.4]
    static let cycleSeconds = cycles
    static let jumpPaws: [Double] = [629,629,629,625,600,575,550,540,540,550,570,600,629,629,629,629]
    static func animation(_ value: Animation) -> Animation {
        guard let cycle = cycles[value.row] else { return value }
        return Animation(row: value.row, frames: 16, interval: cycle / 16, cycleLimit: value.cycleLimit,
                         kicker: value.kicker, title: value.title, tone: value.tone)
    }
    static func row(state: PetState, drag: DragRun?) -> Int {
        if let drag { return drag == .right ? 1 : 2 }
        return animationCatalog[state]?.row ?? 0
    }
    static func position(elapsed: Double, frames: Int = 16, interval: Double) -> (frame: Int, cycles: Int) {
        guard elapsed.isFinite, interval.isFinite, interval > 0, frames > 0 else { return (0,0) }
        let ticks = floor(max(0, elapsed) / interval + 1e-7)
        return (Int(ticks.truncatingRemainder(dividingBy: Double(frames))), Int(min(floor(ticks / Double(frames)), Double(Int.max / 2))))
    }
    static func gazeRow(state: PetState) -> Int { state == .waving ? 10 : 9 }

}

enum AmuRanFrames {
    /// Release decoded frames when the single overlay switches away from this skin.
    static func removeCachedImages() {
        characters.removeAllObjects()
        effects.removeAllObjects()
    }

    private static func resource(_ key: String) -> URL? {
        Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "AmuRanFrames")
    }
    static let hasAllFrames: Bool = {
        for row in AmuRanMotion.cycles.keys {
            for frame in 0..<16 { if resource("character-\(row)-\(frame)") == nil { return false } }
            for sample in 0..<80 {
                for layer in ["back", "front"] { if resource("\(layer)-\(row)-\(sample)") == nil { return false } }
            }
        }
        for costume in ["school", "heart"] {
            for direction in 0..<16 { if resource("gaze-\(costume)-\(direction)") == nil { return false } }
        }
        guard AmuRanInteraction.plan != nil else { return false }
        return ["cheer", "sleep", "left", "right"].allSatisfy { pose in (0..<8).allSatisfy { resource("companion-\(pose)-\($0)") != nil } }
    }()
    private static let characters: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>(); cache.countLimit = 48; cache.totalCostLimit = 56 * 1024 * 1024; return cache
    }()
    private static let effects: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>(); cache.countLimit = 96; cache.totalCostLimit = 56 * 1024 * 1024; return cache
    }()
    private static func draw(_ key: String, in rect: NSRect, effect: Bool = false) -> Bool {
        let cache = effect ? effects : characters, name = key as NSString
        let image: NSImage
        if let cached = cache.object(forKey: name) { image = cached }
        else {
            guard let url = resource(key), let loaded = NSImage(contentsOf: url) else { return false }
            image = loaded; cache.setObject(image, forKey: name, cost: Int(image.size.width * image.size.height) * 4)
        }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        return true
    }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) -> Bool {
        let key = row == 9 || row == 10 ? "gaze-\(row == 9 ? "school" : "heart")-\(frame)" : "character-\(row)-\(frame)"
        return draw(key, in: rect)
    }
    static func drawEffects(state: PetState, drag: DragRun?, time: Double, poseTime: Double, gazeDirection: Int?, in rect: NSRect, front: Bool) {
        guard time.isFinite else { return }
        let t = max(0,time), row = AmuRanMotion.row(state: state, drag: drag)
        let sample = Int(floor(t.truncatingRemainder(dividingBy: 8) * 10 + 1e-7)) % 80
        if front, let companion = AmuRanInteraction.sample(row: row, poseTime: poseTime, effectTime: t, gazeDirection: gazeDirection) {
            let target = NSRect(x: rect.minX + companion.point.x / 448 * rect.width,
                                y: rect.maxY - (companion.point.y + 90) / 640 * rect.height,
                                width: 90 / 448 * rect.width, height: 90 / 640 * rect.height)
            _ = draw("companion-\(companion.side)-\(companion.pose)", in: target, effect: true)
        }

        _ = draw("\(front ? "front" : "back")-\(row)-\(sample)", in: rect, effect: true)
        if front { AmuRanAccents.draw(row: row, poseTime: poseTime, gaze: gazeDirection != nil, in: rect) }
    }
}
