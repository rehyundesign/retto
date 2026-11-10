import AppKit
import Foundation

/// Local, approved Howl motion set. No unapproved gaze artwork is substituted.
enum HowlSkin {
    struct Effect: Decodable { let back: String; let front: String; let anchor: [Double] }
    struct State: Decodable {
        let id: String; let key: String; let variant: String; let row: Int
        let files: [String]; let times: [Double]; let cycle: Double
        let effects: [Effect]; let effectCycle: Double; let effectInterval: Double
        let anchors: [[Double]]; let offsetY: Double
    }
    struct Manifest: Decodable { let version: Int; let states: [State] }
    static let manifest: Manifest? = {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("HowlFrames"),
              let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
    static func normalized(_ row: Int) -> Int { row == 8 ? 7 : (row == 9 || row == 10 ? 0 : row) }
    static func state(row: Int, cookingB: Bool = false) -> State? {
        let r = normalized(row)
        return manifest?.states.first { $0.row == r && $0.variant == (r == 4 && cookingB ? "B" : "A") }
    }
    static var available: Bool {
        guard let m = manifest, m.version == 1, m.states.count == 10 else { return false }
        return m.states.allSatisfy { s in s.files.count == 16 && s.files.allSatisfy { resource($0) != nil } }
    }
    static var placeholder: NSImage { NSImage(size: NSSize(width:7168,height:7680)) }
    static func animation(_ a: Animation) -> Animation {
        guard let s = state(row:a.row) else { return a }
        return Animation(row:s.row,frames:16,interval:s.cycle/16,cycleLimit:a.cycleLimit,
                         kicker:a.kicker,title:a.title,tone:a.tone)
    }
    static func elapsed(row:Int,frame:Int,cycles:Int) -> Double {
        guard let s=state(row:row) else { return 0 }
        return Double(cycles)*s.cycle+s.times.prefix(max(0,min(frame,15))).reduce(0,+)
    }
    static func position(row:Int,time:Double) -> (frame:Int,cycles:Int) {
        guard time.isFinite,let s=state(row:row) else { return (0,0) }
        let t=max(0,time), cycles=Int(min(t/s.cycle,Double(Int.max/2)))
        let phase=t.truncatingRemainder(dividingBy:s.cycle)
        var end=0.0
        for (i,d) in s.times.enumerated() { end+=d; if phase<end-1e-8{return(i,cycles)} }
        return(0,cycles+1)
    }
    private static func resource(_ f:String) -> URL? {
        guard let p=Bundle.main.resourceURL?.appendingPathComponent("HowlFrames").appendingPathComponent(f),
              FileManager.default.fileExists(atPath:p.path) else{return nil};return p
    }
    private static func cache(_ count:Int,_ mb:Int)->NSCache<NSString,NSImage>{let c=NSCache<NSString,NSImage>();c.countLimit=count;c.totalCostLimit=mb*1024*1024;return c}
    private static let characters=cache(48,32), effects=cache(96,40)
    static func purge(){characters.removeAllObjects();effects.removeAllObjects()}
    static func image(_ f:String)->NSImage? {
        let c=f.contains("character-") ? characters : effects
        if let i=c.object(forKey:f as NSString){return i}
        guard let p=resource(f),let data=try? Data(contentsOf:p),let rep=NSBitmapImageRep(data:data),rep.bitmapData != nil else{return nil}
        let im=NSImage(size:NSSize(width:rep.pixelsWide,height:rep.pixelsHigh));im.addRepresentation(rep)
        c.setObject(im,forKey:f as NSString,cost:rep.pixelsWide*rep.pixelsHigh*4);return im
    }
    static func fitted(_ s:State,_ rect:NSRect)->NSRect { rect.offsetBy(dx:0,dy:-s.offsetY/320*rect.height) }
    static func drawCharacter(row:Int,frame:Int,cookingB:Bool,in rect:NSRect){
        guard let s=state(row:row,cookingB:cookingB)else{return}
        image(s.files[max(0,frame)%16])?.draw(in:fitted(s,rect),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
    }
    static func effectIndex(_ s:State,time:Double)->Int {
        guard time.isFinite else{return 0}
        return Int(floor(max(0,time).truncatingRemainder(dividingBy:s.effectCycle)/s.effectInterval+1e-7))%s.effects.count
    }
    static func drawEffects(row:Int,frame:Int,time:Double,cookingB:Bool,front:Bool,in rect:NSRect){
        guard let s=state(row:row,cookingB:cookingB)else{return}
        let e=s.effects[effectIndex(s,time:time)];var target=fitted(s,rect)
        // Foreground light follows the actual held pose; the background keeps its clock.
        if front {let p=s.anchors[max(0,frame)%16];target=target.offsetBy(dx:(p[0]-e.anchor[0])/224*rect.width,dy:-(p[1]-e.anchor[1])/320*rect.height)}
        image(front ? e.front : e.back)?.draw(in:target,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
    }
    static func validate()->Bool {
        guard available,let m=manifest else{return false}
        guard Set(m.states.map{$0.row}) == Set([0,1,2,3,4,5,6,7,11]),normalized(8)==7 else{return false}
        for s in m.states {
            guard s.files.count==16,s.times.count==16,s.anchors.count==16,
                  abs(s.times.reduce(0,+)-s.cycle)<1e-7,
                  abs(Double(s.effects.count)*s.effectInterval-s.effectCycle)<1e-6 else{return false}
            var t=0.0
            for(i,f)in s.files.enumerated(){guard image(f)?.size == NSSize(width:224,height:320),position(row:s.row,time:t+s.times[i]/2).frame==i else{return false};t+=s.times[i]}
            guard position(row:s.row,time:t+0.0001).cycles==1,
                  effectIndex(s,time:0.1) != effectIndex(s,time:0.6) else{return false}
            for e in s.effects {guard resource(e.back) != nil,resource(e.front) != nil else{return false}}
            guard let a=image(s.effects[effectIndex(s,time:0.1)].front)?.tiffRepresentation,
                  let b=image(s.effects[effectIndex(s,time:0.6)].front)?.tiffRepresentation else{return false}
            // Flight has intentional empty front; its rear layer carries the motion.
            if a==b {guard let a=image(s.effects[effectIndex(s,time:0.1)].back)?.tiffRepresentation,
                          let b=image(s.effects[effectIndex(s,time:0.6)].back)?.tiffRepresentation,a != b else{return false}}
        }
        print("Howl: 160 approved cells, independent effect clock, 9 states/drag groups, review alias, cooking A/B and exact clocks passed")
        return true
    }
}

func renderHowlPreview(to path:String, sample:Double=0.8, pose:Int?=nil, held:Bool=false)->Int32 {
    registerRettoFont()
    let cases:[(PetState,DragRun?,Bool)]=[(.idle,nil,false),(.running,nil,false),(.waiting,nil,false),(.waving,nil,false),(.failed,nil,false),(.sleeping,nil,false),(.idle,.left,false),(.idle,.right,false),(.jumping,nil,false),(.jumping,nil,true)]
    let layout=petLayout(scale:224/basePetWidth)
    guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1120,pixelsHigh:1280,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let c=NSGraphicsContext(bitmapImageRep:b)else{return 1}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=c
    for(i,item)in cases.enumerated(){
        let v=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:HowlSkin.placeholder,skin:.howl,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
        v.petScale=224/basePetWidth
        let d=Data("{\"state\":\"\(item.0.rawValue)\",\"sessionId\":\"howl-fixture\",\"projectName\":\"Retto\"}".utf8)
        guard let p=try? JSONDecoder().decode(StatePayload.self,from:d)else{return 1}
        v.apply(p,state:item.0,sessionCount:1,attentionCount:0,isPinned:false)
        if let drag=item.1{v.setDragRunForPreview(drag)}
        let row=item.1.map{$0 == .right ? 1 : 2} ?? animationCatalog[item.0]!.row
        let time=pose.map{Double(max(0,min(15,$0))) * (HowlSkin.state(row:row)!.cycle/16) + 0.001} ?? sample
        v.settleAnimations();v.setHowlVariantForPreview(item.2);v.setHowlTimeForPreview(time)
        if held { v.setFrameForPreview(0) }
        for dark in 0..<2 {
            let x=CGFloat(i%5*224),y=CGFloat((3-(dark*2+i/5))*320)
            (dark==0 ? NSColor.white : NSColor(calibratedWhite:0.14,alpha:1)).setFill();NSRect(x:x,y:y,width:224,height:320).fill()
            NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:224,height:320).clip()
            let a=NSAffineTransform();a.translateX(by:x-layout.petRect.minX,yBy:y-layout.petRect.minY);a.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data=b.representation(using:.png,properties:[:])else{return 1}
    do{try data.write(to:URL(fileURLWithPath:path));return 0}catch{return 1}
}
