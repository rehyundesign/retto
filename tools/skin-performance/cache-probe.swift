import AppKit
import Foundation

private final class WeakFrame {
    weak var image: NSImage?
    let bytes: Int
    init(_ image: NSImage) {
        self.image = image
        bytes = Int(image.size.width * image.size.height) * 4
    }
}

/// Built only into the probe executable, never the installed app.
func runSkinCacheProbe() -> Int32 {
    let cases: [(PetSkin, () -> [NSImage])] = [
        (.jeanne, JeanneSkin.cacheProbeImages), (.hana, HanaFrameCache.cacheProbeImages),
        (.pichiPitch, PichiSkin.cacheProbeImages), (.chocolatHeart, ChocolatHeart.cacheProbeImages),
        (.amuRan, AmuRanFrames.cacheProbeImages)
    ]
    let optimized = CommandLine.arguments.contains("--expect-released")
    var rows: [[String: Any]] = []
    var totalRetained = 0
    for (skin, load) in cases {
        let view = RettoView(frame: NSRect(x: 0, y: 0, width: 224, height: 320),
                             spriteSheet: JeanneSkin.placeholder, skin: skin,
                             onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        var refs: [WeakFrame] = []
        var pixels: [Data] = []
        autoreleasepool {
            let images = load()
            refs = images.map(WeakFrame.init)
            pixels = images.compactMap { $0.tiffRepresentation }
        }
        guard refs.count == 3, pixels.count == 3, refs.allSatisfy({ $0.image != nil }) else {
            print("FAIL: missing cache fixture for \(skin.rawValue)"); return 1
        }
        // Selecting the same skin must preserve useful decoded frames.
        view.skin = skin
        guard refs.allSatisfy({ $0.image != nil }) else { return 1 }
        view.skin = .classic
        let retained = refs.filter { $0.image != nil }
        let bytes = retained.reduce(0) { $0 + $1.bytes }
        totalRetained += bytes
        if optimized && !retained.isEmpty {
            print("FAIL: cache retained after leaving \(skin.rawValue)"); return 1
        }
        // Reloaded character/effect pixels must remain identical.
        let samePixels = autoreleasepool { load().compactMap { $0.tiffRepresentation } == pixels }
        guard samePixels else { print("FAIL: changed pixels for \(skin.rawValue)"); return 1 }
        rows.append(["skin": skin.rawValue, "retainedFrames": retained.count, "retainedDecodedBytes": bytes,
                     "sameSkinCachePreserved": true, "reloadedPixelsIdentical": true])
        // Return to the fixture skin, then leave again to clear the reloaded frames.
        view.skin = skin
        view.skin = .classic
    }
    let result: [String: Any] = ["ok": true, "optimized": optimized, "skins": rows,
                                "retainedDecodedBytes": totalRetained]
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    return 0
}
