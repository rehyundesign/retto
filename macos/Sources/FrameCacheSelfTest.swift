import AppKit
import Darwin

func runFrameCacheSelfTest() -> Int32 {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<4 { for x in 0..<4 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bitmap.bitmapData![offset] = UInt8(x * 85)
            bitmap.bitmapData![offset + 1] = UInt8(y * 85)
            bitmap.bitmapData![offset + 2] = 128
            bitmap.bitmapData![offset + 3] = x == 0 ? 0 : 255
        } }
        let data = bitmap.representation(using: .png, properties: [:])!
        let urls = (0..<3).map { directory.appendingPathComponent("\($0).png") }
        for url in urls { try data.write(to: url) }
        let cache = DecodedFrameCache(byteLimit: 4096)
        guard let a = cache.image(at: urls[0]), a.size == NSSize(width: 4, height: 4),
              cache.image(at: urls[0]) === a, cache.decodeCount == 1 else { return 1 }
        _ = cache.image(at: urls[1]); _ = cache.image(at: urls[0])
        guard cache.decodeCount == 2, cache.retainedBytes <= cache.byteLimit else { return 1 }
        let small = DecodedFrameCache(byteLimit: 128)
        _ = small.image(at: urls[0]); _ = small.image(at: urls[1]); _ = small.image(at: urls[0])
        guard small.decodeCount == 3, small.retainedBytes <= small.byteLimit,
              cache.image(at: directory.appendingPathComponent("missing.png")) == nil else { return 1 }
        cache.removeAllObjects()
        guard cache.retainedBytes == 0 else { return 1 }
        let tiny = DecodedFrameCache(byteLimit: 1)
        guard tiny.image(at: urls[0]) != nil, tiny.retainedBytes == 0 else { return 1 }
        // Exercise real lossless compression, decompression and every sample in one complete cycle.
        let real = DecodedFrameCache(byteLimit: 48 * 1024 * 1024)
        for cycle in 0..<2 {
            for index in 0..<64 {
                let url = AngelSkin.root.appendingPathComponent(String(format: "running/%03d.png", index))
                guard let image = real.image(at: url), let original = NSImage(contentsOf: url) else { return 1 }
                func pixels(_ image: NSImage) -> Data {
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 544, pixelsHigh: 544,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    image.draw(in: NSRect(x: 0, y: 0, width: 544, height: 544))
                    NSGraphicsContext.restoreGraphicsState()
                    return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                }
                guard autoreleasepool(invoking: { pixels(image) == pixels(original) }),
                      real.retainedBytes <= real.byteLimit else { return 1 }
            }
            guard real.decodeCount == 64 else { print("Repeated PNG decode", cycle, real.decodeCount); return 1 }
        }
        guard AngelSkin.displaySample(row: 11, time: 0.01, alternateIdle: false, flight: false)
                == AngelSkin.displaySample(row: 11, time: 0.06, alternateIdle: false, flight: false),
              AngelSkin.displaySample(row: 7, time: 0.01, alternateIdle: false, flight: false)
                != AngelSkin.displaySample(row: 7, time: 0.06, alternateIdle: false, flight: false) else { return 1 }
        print("PASS decoded cache: cache hit identity, actual pixel cost, LRU eviction, missing image, oversized image, purge")
        return 0
    } catch { print(error); return 1 }
}

/// Same drawing workload in the baseline and optimized binaries; no account data or live UI.
func benchmarkAngelFrames() -> Int32 {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 544, pixelsHigh: 544,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    let start = ProcessInfo.processInfo.systemUptime, cpu = clock()
    for i in 0..<512 {
        autoreleasepool {
            context.cgContext.clear(CGRect(x: 0, y: 0, width: 544, height: 544))
            _ = AngelSkin.draw(row: 7, time: Double(i % 64) * 0.05,
                in: NSRect(x: 0, y: 0, width: 448, height: 640))
        }
    }
    print("{\"frames\":512,\"seconds\":\(ProcessInfo.processInfo.systemUptime-start),\"cpuSeconds\":\(Double(clock()-cpu)/Double(CLOCKS_PER_SEC))}")
    return 0
}
