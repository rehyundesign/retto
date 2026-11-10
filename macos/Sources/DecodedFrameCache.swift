import AppKit
import ImageIO

/// Retain decoded pixels, rather than file-backed images that can decode again on every draw.
/// All callers run on the main thread. A deterministic LRU keeps one shared hard pixel budget.
final class DecodedFrameCache {
    static let angel = DecodedFrameCache(byteLimit: 96 * 1024 * 1024)
    private struct Entry { let image: NSImage; let bytes: Int; var access: UInt64 }
    private var entries: [String: Entry] = [:]
    private var access: UInt64 = 0
    let byteLimit: Int
    private(set) var retainedBytes = 0
    private(set) var decodeCount = 0
    init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

    func removeAllObjects() { entries.removeAll(); retainedBytes = 0 }

    func image(at url: URL) -> NSImage? {
        let key = url.path
        access &+= 1
        if var entry = entries[key] {
            entry.access = access; entries[key] = entry
            return entry.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let context = CGContext(data: nil, width: original.width, height: original.height,
                  bitsPerComponent: 8, bytesPerRow: original.width * 4,
                  space: original.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
        guard let pixels = context.makeImage() else { return nil }
        let image = NSImage(cgImage: pixels, size: NSSize(width: original.width, height: original.height))
        image.cacheMode = .never
        decodeCount += 1
        let bytes = context.bytesPerRow * context.height
        if bytes <= byteLimit {
            while retainedBytes > byteLimit - bytes, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
                retainedBytes -= oldest.value.bytes; entries.removeValue(forKey: oldest.key)
            }
            entries[key] = Entry(image: image, bytes: bytes, access: access)
            retainedBytes += bytes
        }
        return image
    }
}
