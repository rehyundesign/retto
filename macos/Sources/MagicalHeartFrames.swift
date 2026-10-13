import AppKit
import Foundation

enum MagicalHeartFrames {
    static let hasAllFrames: Bool = {
        for row in MagicalHeartMotion.cycleSeconds.keys {
            for frame in 0..<16 {
                guard resource(row: row, frame: frame) != nil else { return false }
            }
        }
        return (0..<16).allSatisfy { resource(row: $0 < 8 ? 9 : 10, frame: $0 % 8) != nil }
    }()

    private static let cache: NSCache<NSString, NSImage> = {
        let value = NSCache<NSString, NSImage>()
        value.countLimit = 48
        value.totalCostLimit = 56 * 1024 * 1024
        return value
    }()

    static var placeholder: NSImage { NSImage(size: NSSize(width: 7168, height: 7680)) }

    private static func resource(row: Int, frame: Int) -> URL? {
        let key = row == 9 || row == 10 ? "gaze-\((row - 9) * 8 + frame)" : "character-\(row)-\(frame)"
        return Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "MagicalHeartFrames")
    }

    static func draw(row: Int, frame: Int, in rect: NSRect) -> Bool {
        guard hasAllFrames, let url = resource(row: row, frame: frame) else { return false }
        let key = url.lastPathComponent as NSString
        let image: NSImage
        if let cached = cache.object(forKey: key) { image = cached }
        else {
            guard let loaded = NSImage(contentsOf: url), loaded.size == NSSize(width: 448, height: 640) else { return false }
            image = loaded
            cache.setObject(image, forKey: key, cost: 448 * 640 * 4)
        }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        return true
    }
}
