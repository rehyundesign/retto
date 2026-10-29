import AppKit
import Foundation

/// 승인된 motion-v27 원본 캐릭터와 별도로 진행하는 앞·뒤 마법 효과.
enum ChocolatHeart {
    /// Release decoded frames when the single overlay switches away from this skin.
    static func removeCachedImages() {
        cache.removeAllObjects()
    }

    static let speed = 0.75
    static let rows = [0,7,8,6,5,3,4,11,1,2]
    static let names = ["idle","running","review","waiting","failed","waving","jumping","sleeping","drag-right","drag-left"]
    static let counts = [16,16,12,12,12,16,12,12,8,8]
    static let intervals = [0.15,0.15,0.1,0.1,0.1,0.15,0.1,0.2,0.085,0.085]
    private static let cache: NSCache<NSString,NSImage> = {
        let result = NSCache<NSString,NSImage>();result.countLimit=96;result.totalCostLimit=96*1024*1024;return result
    }()
    static var available: Bool {
        Bundle.main.url(forResource:"character-0-0",withExtension:"webp",subdirectory:"ChocolatHeartFrames") != nil
    }
    static var placeholder: NSImage { NSImage(size:NSSize(width:1792,height:3840)) }
    static func animation(_ original: Animation) -> Animation {
        guard let i=rows.firstIndex(of:original.row) else { return original }
        return Animation(row:original.row,frames:counts[i],interval:intervals[i]/speed,
                         cycleLimit:original.cycleLimit,kicker:original.kicker,title:original.title,tone:original.tone)
    }
    static func image(_ name: String) -> NSImage? {
        if let image=cache.object(forKey:name as NSString) { return image }
        guard let url=Bundle.main.url(forResource:name,withExtension:"webp",subdirectory:"ChocolatHeartFrames"),let image=NSImage(contentsOf:url) else { return nil }
        cache.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height)*4);return image
    }
    static func draw(_ image: NSImage?, in rect: NSRect) {
        image?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
    }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) {
        draw(image("character-\(row)-\(frame)"),in:rect)
    }
    static func drawEffects(row: Int, time: TimeInterval, front: Bool, in rect: NSRect) {
        guard let index=rows.firstIndex(of:row) else { return }
        let frame=Int(max(0,time)*speed*20)%256
        draw(image("\(names[index])-\(front ? "front":"back")-\(frame)"),in:rect)
    }
    static func validate() -> Bool {
        for (i,row) in rows.enumerated() {
            for frame in 0..<counts[i] { if image("character-\(row)-\(frame)")==nil { return false } }
            for layer in ["back","front"] { for frame in 0..<256 {
                if Bundle.main.url(forResource:"\(names[i])-\(layer)-\(frame)",withExtension:"webp",subdirectory:"ChocolatHeartFrames")==nil { return false }
            } }
        }
        func snapshot(_ time: Double) -> Data? {
            let canvas=NSImage(size:NSSize(width:224,height:320));canvas.lockFocus()
            drawEffects(row:7,time:time,front:false,in:NSRect(x:0,y:0,width:224,height:320))
            drawCharacter(row:7,frame:0,in:NSRect(x:0,y:0,width:224,height:320))
            drawEffects(row:7,time:time,front:true,in:NSRect(x:0,y:0,width:224,height:320))
            canvas.unlockFocus();return canvas.tiffRepresentation
        }
        guard let first=snapshot(0.13),let second=snapshot(0.83),first != second else { return false }
        for animation in animationCatalog.values {
            let mapped=Self.animation(animation)
            guard let i=rows.firstIndex(of:animation.row),mapped.frames==counts[i],abs(mapped.interval*speed-intervals[i]) < 0.000001 else { return false }
        }
        return true
    }
}
