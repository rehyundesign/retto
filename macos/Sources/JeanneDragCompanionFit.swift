import AppKit

/// Runtime-only separation of Finn in four oversized v56 right-drag drawings.
/// The original decoded pixels outside Finn's alpha component are copied unchanged.
/// No packaged source image, Retto pose, playback slot or effect layer is replaced.
enum JeanneDragCompanionFit {
    private static let affectedFrames: Set<Int> = [2, 3, 10, 11]
    private static let referenceCoreArea: CGFloat = 10_500
    private final class Parts {
        let body: NSImage
        let companion: NSImage
        let bounds: CGRect
        let anchor: CGPoint
        let scale: CGFloat
        let sourceArea: Int
        let protectedPixels: Int
        init(body: NSImage, companion: NSImage, bounds: CGRect, anchor: CGPoint,
             scale: CGFloat, sourceArea: Int, protectedPixels: Int) {
            self.body = body; self.companion = companion; self.bounds = bounds
            self.anchor = anchor; self.scale = scale; self.sourceArea = sourceArea
            self.protectedPixels = protectedPixels
        }
    }
    private static let cache: NSCache<NSString, Parts> = {
        let result = NSCache<NSString, Parts>()
        result.countLimit = 4; result.totalCostLimit = 8 * 1024 * 1024
        return result
    }()
    static func removeCachedImages() { cache.removeAllObjects() }

    private static func image(_ rep: NSBitmapImageRep) -> NSImage {
        let result = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        result.addRepresentation(rep); return result
    }
    private static func bitmap(width: Int, height: Int, matching original: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: original.colorSpaceName, bitmapFormat: original.bitmapFormat,
            bytesPerRow: width * 4, bitsPerPixel: 32) else { return nil }
        return result.retagging(with: original.colorSpace) ?? result
    }
    private static func split(_ original: NSImage) -> Parts? {
        guard let rep = original.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              rep.pixelsWide == 448, rep.pixelsHigh == 640, rep.samplesPerPixel == 4,
              rep.bitsPerSample == 8, !rep.isPlanar, !rep.bitmapFormat.contains(.alphaFirst),
              let pixels = rep.bitmapData else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh, count = width * height
        var labels = [Int32](repeating: 0, count: count)
        struct Component {
            var area = 0, green = 0, minX = 448, minY = 640, maxX = 0, maxY = 0
        }
        var components = [Component()]
        var queue: [Int] = []; queue.reserveCapacity(count)
        // Opaque cores identify the two genuinely separate drawings. A fully-alpha
        // flood fill would merge them through faint generated edge/noise pixels.
        for index in 0..<count {
            let x = index % width, y = index / width
            guard labels[index] == 0, pixels[y * rep.bytesPerRow + x * 4 + 3] > 20 else { continue }
            let label = Int32(components.count)
            var component = Component(), pending = [index]
            labels[index] = label
            while let current = pending.popLast() {
                queue.append(current)
                let x = current % width, y = current / width, offset = y * rep.bytesPerRow + x * 4
                component.area += 1
                if pixels[offset + 3] > 204 && Double(pixels[offset + 1]) > Double(pixels[offset]) * 1.1
                    && Double(pixels[offset + 1]) > Double(pixels[offset + 2]) * 1.08 { component.green += 1 }
                component.minX = min(component.minX,x); component.maxX = max(component.maxX,x)
                component.minY = min(component.minY,y); component.maxY = max(component.maxY,y)
                for dy in -1...1 { for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < width, yy >= 0, yy < height else { continue }
                    let next = yy * width + xx
                    if labels[next] == 0 && pixels[yy * rep.bytesPerRow + xx * 4 + 3] > 20 {
                        labels[next] = label; pending.append(next)
                    }
                } }
            }
            components.append(component)
        }
        guard let selected = components.indices.dropFirst().filter({
            components[$0].area >= 14_000 && components[$0].area <= 30_000
                && components[$0].green >= 100 && components[$0].maxY < 400
        }).max(by: { components[$0].green < components[$1].green }) else { return nil }
        let core = components[selected], selectedLabel = Int32(selected)
        // Assign low-alpha fringes to their nearest opaque core without joining the
        // core labels. Retto's opaque pixels can never be assigned to Finn.
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]; cursor += 1
            let x = current % width, y = current / width
            for dy in -1...1 { for dx in -1...1 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, xx < width, yy >= 0, yy < height else { continue }
                let next = yy * width + xx
                if labels[next] == 0 && pixels[yy * rep.bytesPerRow + xx * 4 + 3] > 0 {
                    labels[next] = labels[current]; queue.append(next)
                }
            } }
        }
        var minX = width, minY = height, maxX = 0, maxY = 0
        for index in 0..<count where labels[index] == selectedLabel {
            minX = min(minX,index % width); maxX = max(maxX,index % width)
            minY = min(minY,index / width); maxY = max(maxY,index / width)
        }
        let cropWidth = maxX-minX+1, cropHeight = maxY-minY+1
        guard let body = bitmap(width:width,height:height,matching:rep), let bodyData = body.bitmapData,
              let companion = bitmap(width:cropWidth,height:cropHeight,matching:rep), let companionData = companion.bitmapData else { return nil }
        memset(companionData,0,companion.bytesPerRow*cropHeight)
        var protectedPixels = 0
        for y in 0..<height { for x in 0..<width {
            let source = y*rep.bytesPerRow+x*4, target = y*body.bytesPerRow+x*4
            if labels[y*width+x] == selectedLabel {
                memset(bodyData+target,0,4)
                memcpy(companionData+(y-minY)*companion.bytesPerRow+(x-minX)*4,pixels+source,4)
            } else {
                memcpy(bodyData+target,pixels+source,4)
                if pixels[source+3] > 20 { protectedPixels += 1 }
                guard memcmp(bodyData+target,pixels+source,4) == 0 else { return nil }
            }
        } }
        guard protectedPixels > 45_000 else { return nil }
        return Parts(body:image(body),companion:image(companion),
            bounds:CGRect(x:minX,y:minY,width:cropWidth,height:cropHeight),
            anchor:CGPoint(x:CGFloat(core.minX+core.maxX+1)/2,y:CGFloat(core.minY+core.maxY+1)/2),
            scale:sqrt(referenceCoreArea/CGFloat(core.area)),sourceArea:core.area,protectedPixels:protectedPixels)
    }
    private static func parts(_ image: NSImage, frame: Int, key: String) -> Parts? {
        guard affectedFrames.contains(frame) else { return nil }
        if let cached = cache.object(forKey:key as NSString) { return cached }
        guard let result = split(image) else { return nil }
        cache.setObject(result,forKey:key as NSString,cost:448*640*4+Int(result.bounds.width*result.bounds.height)*4)
        return result
    }
    static func draw(_ original: NSImage, frame: Int, key: String, in rect: NSRect) -> Bool {
        guard let p = parts(original,frame:frame,key:key) else { return false }
        p.body.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
        let anchor = CGPoint(x:rect.minX+p.anchor.x/448*rect.width,y:rect.maxY-p.anchor.y/640*rect.height)
        let unscaled = CGRect(x:rect.minX+p.bounds.minX/448*rect.width,y:rect.maxY-p.bounds.maxY/640*rect.height,
                              width:p.bounds.width/448*rect.width,height:p.bounds.height/640*rect.height)
        let fitted = CGRect(x:anchor.x+(unscaled.minX-anchor.x)*p.scale,y:anchor.y+(unscaled.minY-anchor.y)*p.scale,
                            width:unscaled.width*p.scale,height:unscaled.height*p.scale)
        p.companion.draw(in:fitted,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
        return true
    }
    static func validate(_ images: [(String, NSImage)], verbose: Bool = false) -> Bool {
        guard images.count == 16 else { return false }
        var repaired = 0
        for (frame,pair) in images.enumerated() {
            let result = parts(pair.1,frame:frame,key:pair.0)
            if affectedFrames.contains(frame) {
                guard let p=result,p.scale>0.6,p.scale<0.9,p.protectedPixels>45_000 else { return false }
                func render(_ corrected: Bool) -> NSBitmapImageRep? {
                    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:448,pixelsHigh:640,
                        bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
                        bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
                    memset(bitmap.bitmapData!,0,bitmap.bytesPerRow*640)
                    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
                    let target=NSRect(x:0,y:0,width:448,height:640)
                    if corrected { _ = draw(pair.1,frame:frame,key:pair.0,in:target) }
                    else { pair.1.draw(in:target,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high]) }
                    NSGraphicsContext.restoreGraphicsState();return bitmap
                }
                guard let before=render(false),let after=render(true),
                      let body=p.body.representations.first as? NSBitmapImageRep else { return false }
                var changedRettoPixels=0
                for y in 0..<640 { for x in 0..<448 where body.bitmapData![y*body.bytesPerRow+x*4+3]>204 {
                    if memcmp(before.bitmapData!+y*before.bytesPerRow+x*4,
                              after.bitmapData!+y*after.bytesPerRow+x*4,4) != 0 { changedRettoPixels+=1 }
                } }
                guard changedRettoPixels==0 else { print("Finn correction changed Retto pixels: frame \(frame), \(changedRettoPixels)");return false }
                guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(ceil(p.companion.size.width*p.scale)),
                    pixelsHigh:Int(ceil(p.companion.size.height*p.scale)),bitsPerSample:8,samplesPerPixel:4,
                    hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                      let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return false }
                memset(bitmap.bitmapData!,0,bitmap.bytesPerRow*bitmap.pixelsHigh)
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
                p.companion.draw(in:NSRect(x:0,y:0,width:p.companion.size.width*p.scale,height:p.companion.size.height*p.scale),
                    from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
                NSGraphicsContext.restoreGraphicsState()
                var area=0
                for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide where bitmap.bitmapData![y*bitmap.bytesPerRow+x*4+3]>20 { area+=1 } }
                guard abs(CGFloat(area)/referenceCoreArea-1)<0.10 else { print("Finn area mismatch: frame \(frame), \(area)"); return false }
                repaired+=1
            } else if result != nil { return false }
        }
        if verbose { print("Finn right drag: \(repaired) outlier frames normalized; Retto pixels preserved; 12 other frames bypass correction") }
        return repaired == 4
    }
}
