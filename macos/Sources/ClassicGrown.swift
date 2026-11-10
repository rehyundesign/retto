import AppKit

/// Approved grown Retto cells. The legacy atlas remains a fallback when absent.
enum ClassicGrown {
    struct Motion: Decodable {
        let files: [String]
        let durations: [Double]
    }
    struct Manifest: Decodable {
        let rows: [String: Motion]
        let gaze: [String]?
    }
    private static let root = Bundle.main.resourceURL?.appendingPathComponent("ClassicGrownFrames")
    private static let manifest: Manifest? = {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let m = try? JSONDecoder().decode(Manifest.self, from: data),
              [0,1,2,3,4,5,6,7,8,11].allSatisfy({ row in
                  guard let s = m.rows[String(row)], !s.files.isEmpty,
                        s.files.count == s.durations.count,
                        s.durations.allSatisfy({ $0 > 0 && $0.isFinite }) else { return false }
                  return s.files.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
              }), (m.gaze.map { files in files.count == 16 && files.allSatisfy {
                  FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
              }} ?? true) else { return nil }
        return m
    }()
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 24; c.totalCostLimit = 28 * 1024 * 1024; return c
    }()
    static func removeCachedImages() { cache.removeAllObjects() }
    static var available: Bool { manifest != nil }
    static var gazeAvailable: Bool { manifest?.gaze?.count == 16 }
    static func motion(row: Int) -> Motion? { manifest?.rows[String(row)] }
    static func animation(_ original: Animation) -> Animation {
        guard let s = motion(row: original.row) else { return original }
        return Animation(row: original.row, frames: s.files.count,
                         interval: s.durations.reduce(0,+) / Double(s.files.count),
                         cycleLimit: original.cycleLimit, kicker: original.kicker,
                         title: original.title, tone: original.tone)
    }
    static func elapsed(row: Int, frame: Int, cycles: Int) -> Double {
        guard let s = motion(row: row) else { return 0 }
        return Double(cycles) * s.durations.reduce(0,+) + s.durations.prefix(frame).reduce(0,+)
    }
    static func position(row: Int, elapsed: Double) -> (frame: Int, cycles: Int) {
        guard let s = motion(row: row) else { return (0,0) }
        let cycle = s.durations.reduce(0,+), t = max(0, elapsed)
        let cycles = Int(t / cycle), phase = t - Double(cycles) * cycle
        var end = 0.0
        for (i, d) in s.durations.enumerated() {
            end += d
            if phase < end - 0.0000001 { return (i, cycles) }
        }
        return (0, cycles + 1)
    }
    static func image(row: Int, frame: Int) -> NSImage? {
        let gaze = row == 9 || row == 10
        let file: String
        if gaze, let directions = manifest?.gaze {
            let direction = frame + (row == 10 ? 8 : 0)
            guard (0..<8).contains(frame), directions.indices.contains(direction) else { return nil }
            file = directions[direction]
        } else {
            // Compatibility for an older resource package without directional art.
            guard let s = motion(row: gaze ? 0 : row),
                  s.files.indices.contains(gaze ? 0 : frame) else { return nil }
            file = s.files[gaze ? 0 : frame]
        }
        guard let root else { return nil }
        if let image = cache.object(forKey: file as NSString) { return image }
        guard let image = NSImage(contentsOf: root.appendingPathComponent(file)) else { return nil }
        cache.setObject(image, forKey: file as NSString, cost: 448 * 640 * 4)
        return image
    }
    @discardableResult static func draw(row: Int, frame: Int, in rect: NSRect) -> Bool {
        guard let image = image(row: row, frame: frame) else { return false }
        // Shared seated/gait camera preserves pose displacements. Sleep has its own floor.
        // Align the approved source floor with the existing native ground shadow.
        let sourceFloor: CGFloat = row == 11 ? 607 : 593
        let grounded = rect.offsetBy(dx: 0, dy: -rect.height * (628 - sourceFloor) / 640)
        image.draw(in: grounded, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        return true
    }
    static func selfTest() -> Bool {
        guard available else { return false }
        for row in [0,1,2,3,4,5,6,7,8,11] {
            guard let s = motion(row: row), s.files.count == (row == 0 ? 9 : 16) else { return false }
            var start = 0.0
            for (i,d) in s.durations.enumerated() {
                guard position(row: row, elapsed: start + d / 2).frame == i,
                      image(row: row, frame: i) != nil else { return false }
                start += d
            }
            let p = position(row: row, elapsed: start + 0.0001)
            guard p.frame == 0, p.cycles == 1 else { return false }
        }
        return true
    }
    static func gazeSelfTest() -> Bool {
        guard gazeAvailable else { return false }
        var decoded = Set<Data>()
        for direction in 0..<16 {
            guard let image = image(row: direction < 8 ? 9 : 10, frame: direction % 8),
                  let tiff = image.tiffRepresentation else { return false }
            decoded.insert(tiff)
        }
        return decoded.count == 16 && image(row: 9, frame: 8) == nil && image(row: 10, frame: -1) == nil
    }
}
