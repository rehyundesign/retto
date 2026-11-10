import AppKit
import ImageIO
import Compression

/// Keep lossless compressed pixels and only the most recently drawn decoded frame.
/// Main-thread callers share a strict budget that includes both retained representations.
final class DecodedFrameCache {
    static let angel = DecodedFrameCache(byteLimit: 48 * 1024 * 1024)
    private struct Entry {
        let pixels: Data
        let compressed: Bool
        let width: Int
        let height: Int
        let colorSpace: CGColorSpace
        var access: UInt64
        var rawBytes: Int { width * height * 4 }
    }
    private var entries: [String: Entry] = [:]
    private var hot: (key: String, image: NSImage, bytes: Int)?
    private var compressedBytes = 0
    private var access: UInt64 = 0
    let byteLimit: Int
    var retainedBytes: Int { compressedBytes + (hot?.bytes ?? 0) }
    private(set) var decodeCount = 0
    init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }

    func removeAllObjects() { entries.removeAll(); compressedBytes = 0; hot = nil }

    private func trim() {
        while retainedBytes > byteLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            compressedBytes -= oldest.value.pixels.count
            entries.removeValue(forKey: oldest.key)
        }
        if retainedBytes > byteLimit { hot = nil }
    }

    func image(at url: URL) -> NSImage? {
        let key = url.path
        access &+= 1
        if var entry = entries[key] {
            entry.access = access; entries[key] = entry
            if let hot, hot.key == key { return hot.image }
            guard let image = image(from: entry) else { return nil }
            hot = (key, image, entry.rawBytes); trim()
            return image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let context = CGContext(data: nil, width: original.width, height: original.height,
                  bitsPerComponent: 8, bytesPerRow: original.width * 4,
                  space: original.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
        let count = context.bytesPerRow * context.height
        var compressed = Data(count: count + 65536)
        let written = compressed.withUnsafeMutableBytes { output in
            compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                data.assumingMemoryBound(to: UInt8.self), count, nil, COMPRESSION_LZ4)
        }
        let useCompressed = written > 0 && written < count
        if useCompressed {
            compressed = compressed.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: written) }
        }
        else { compressed = Data(bytes: data, count: count) }
        let entry = Entry(pixels: compressed, compressed: useCompressed, width: original.width,
            height: original.height, colorSpace: context.colorSpace!, access: access)
        guard let image = image(from: entry) else { return nil }
        decodeCount += 1
        entries[key] = entry; compressedBytes += entry.pixels.count
        hot = (key, image, count); trim()
        return image
    }

    private func image(from entry: Entry) -> NSImage? {
        var pixels = entry.pixels
        if entry.compressed {
            pixels = Data(count: entry.rawBytes)
            let written = pixels.withUnsafeMutableBytes { output in
                entry.pixels.withUnsafeBytes { input in
                    compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                        input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZ4)
                }
            }
            guard written == entry.rawBytes else { return nil }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: entry.width, height: entry.height, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: entry.width * 4, space: entry.colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: entry.width, height: entry.height))
        result.cacheMode = .never
        return result
    }
}
