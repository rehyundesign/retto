import AppKit
import Foundation

/// Approved integrated cat-and-companion drawings; no limb/head/pet compositing.
enum HachupingSkin {
    struct Effect: Decodable { let back:String; let front:String }
    struct Motion: Decodable {let key:String;let files:[String];let interval:Double;let effects:[Effect];let effectInterval:Double;var cycle:Double{Double(files.count)*interval}}
    struct Manifest: Decodable {let version:Int;let cell:[Int];let states:[Motion];let neutral:String}
    static let root=Bundle.main.resourceURL?.appendingPathComponent("HachupingFrames")
    static let manifest:Manifest?={guard let root,let d=try? Data(contentsOf:root.appendingPathComponent("manifest.json"))else{return nil};return try? JSONDecoder().decode(Manifest.self,from:d)}()
    static let working=["mirror","perfume","bell","puff"]
    struct Policy {
        private var bag:[String]=[]
        private var entry:String?;private var last:String?
        private(set) var workingKey="mirror"
        mutating func select(_ state:PetState,session:String) -> Bool {
            let active=state == .running || state == .review
            let next=active ? "working:"+session : state.rawValue+":"+session
            guard next != entry else{return false};entry=next
            guard active else{return false}
            if bag.isEmpty {bag=HachupingSkin.working.shuffled();if bag.last == last {bag.swapAt(0,bag.count-1)}}
            workingKey=bag.removeLast();last=workingKey;return true
        }
    }
    static func key(state:PetState,drag:DragRun?,working:String)->String {
        if let drag{return drag == .right ? "drag-right":"drag-left"}
        switch state {
        case .idle:return "idle"
        case .running,.review:return working
        case .waiting:return "harp"
        case .failed:return "failed"
        case .waving:return "princess"
        case .jumping:return "jump"
        case .sleeping:return "sleeping"
        }
    }
    static func motion(_ key:String)->Motion? {
        guard let m=manifest else{return nil}
        return m.states.first{$0.key==key}
    }
    static var available:Bool {
        guard let m=manifest,m.version==2,m.cell==[448,640],m.states.count==13 else{return false}
        return m.states.allSatisfy{$0.files.count==16 && $0.files.allSatisfy{resource($0) != nil}} && resource(m.neutral) != nil
    }
    static var placeholder:NSImage{NSImage(size:NSSize(width:7168,height:7680))}
    static func animation(_ a:Animation,key:String)->Animation {
        guard let m=motion(key)else{return a}
        return Animation(row:a.row,frames:m.files.count,interval:m.interval,cycleLimit:key == "princess" ? nil:a.cycleLimit,kicker:a.kicker,title:a.title,tone:a.tone)
    }
    static func position(_ key:String,time:Double)->(frame:Int,cycles:Int){
        guard let m=motion(key),time.isFinite else{return(0,0)}
        let tick=Int(min(floor(max(0,time)/m.interval+1e-7),Double(Int.max/2)))
        return(tick%m.files.count,tick/m.files.count)
    }
    static func effectIndex(_ key:String,time:Double)->Int {
        guard let m=motion(key),time.isFinite,!m.effects.isEmpty else{return 0}
        return Int(floor(max(0,time).truncatingRemainder(dividingBy:Double(m.effects.count)*m.effectInterval)/m.effectInterval+1e-7))%m.effects.count
    }
    private static func resource(_ name:String)->URL?{guard let p=root?.appendingPathComponent(name),FileManager.default.fileExists(atPath:p.path)else{return nil};return p}
    private static let cache:NSCache<NSString,NSImage>={let c=NSCache<NSString,NSImage>();c.countLimit=100;c.totalCostLimit=100*1024*1024;return c}()
    static func purge(){cache.removeAllObjects()}
    static func image(_ f:String)->NSImage? {
        if let i=cache.object(forKey:f as NSString){return i}
        guard let url=resource(f),let d=try? Data(contentsOf:url),let r=NSBitmapImageRep(data:d),r.bitmapData != nil else{return nil}
        let i=NSImage(size:NSSize(width:r.pixelsWide,height:r.pixelsHigh));i.addRepresentation(r);cache.setObject(i,forKey:f as NSString,cost:r.pixelsWide*r.pixelsHigh*4);return i
    }
    /// Fixed projection for the two wide gait sequences. Preserve ground contact at source y=602.
    static func fitted(_ key:String,in rect:NSRect)->NSRect {
        guard key == "drag-right" || key == "drag-left" else{return rect}
        let factor:CGFloat=1.32
        return NSRect(x:rect.midX-rect.width*factor/2,
                      y:rect.minY-rect.height*(1-602.0/640)*(factor-1),
                      width:rect.width*factor,height:rect.height*factor)
    }
    static func validateDragFit()->Bool {
        let r=NSRect(x:48,y:20,width:224,height:320)
        for key in ["drag-right","drag-left"] {
            let f=fitted(key,in:r)
            guard abs(f.width/r.width-1.32)<0.000001,abs(f.height/r.height-1.32)<0.000001,
                  abs((f.minY+f.height*38/640)-(r.minY+r.height*38/640))<0.000001,
                  abs(f.midX-r.midX)<0.000001 else{return false}
        }
        for key in ["idle","gaze","sleeping","jump","princess","harp","failed"]+working {guard fitted(key,in:r)==r else{return false}}
        print("Drag fit: both directions 132%, equal axes, shared ground, other states unchanged")
        return true
    }
    static func drawCharacter(key:String,frame:Int,in rect:NSRect){guard let m=motion(key)else{return};image(m.files[max(0,frame)%m.files.count])?.draw(in:fitted(key,in:rect),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])}
    static func drawEffects(key:String,time:Double,front:Bool,in rect:NSRect){guard let m=motion(key),!m.effects.isEmpty else{return};let e=m.effects[effectIndex(key,time:time)];image(front ? e.front:e.back)?.draw(in:fitted(key,in:rect),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])}
    static func validate()->Bool {
        guard available,let m=manifest,validateDragFit() else{return false}
        var p=Policy(),previous="";var seen=Set<String>()
        for i in 0..<300 {
            _=p.select(.idle,session:"test");guard p.select(.running,session:"test")else{return false}
            let chosen=p.workingKey;guard chosen != previous,working.contains(chosen)else{return false};previous=chosen;seen.insert(chosen)
            guard !p.select(.review,session:"test"),!p.select(.running,session:"test"),p.workingKey==chosen else{return false}
            if i%working.count==working.count-1 {guard seen==Set(working)else{return false};seen=[]}
        }
        for s in m.states {
            for(i,f)in s.files.enumerated(){guard image(f)?.size==NSSize(width:448,height:640),position(s.key,time:(Double(i)+0.5)*s.interval).frame==i else{return false}}
            guard position(s.key,time:s.cycle+0.001).cycles==1,s.effects.count==Int(round(s.cycle*20))else{return false}
            for e in s.effects {guard resource(e.back) != nil,resource(e.front) != nil else{return false}}
        }
        guard let idle=motion("idle"),let gaze=motion("gaze"),idle.files != gaze.files,
              idle.files.count==16,abs(idle.cycle-3.2)<0.000001,
              position("idle",time:0.1).frame != position("idle",time:1.7).frame,
              effectIndex("idle",time:0.1) != effectIndex("idle",time:0.6) else{return false}
        print("Idle:16 NEW breathing/blink drawings,200ms each,3.2s;cursor remains separate")
        guard key(state:.waiting,drag:nil,working:"mirror")=="harp",key(state:.failed,drag:nil,working:"mirror")=="failed",!working.contains("harp"),!working.contains("failed"),working.count==4 else{return false}
        guard key(state:.waving,drag:nil,working:"mirror")=="princess",key(state:.jumping,drag:nil,working:"harp")=="jump" else{return false}
        print("Hachuping current:208 integrated drawings/13groups;4-way work bag;Lime waiting;sad failed;20Hz effects;100/200/400ms clocks;300 shuffle entries passed")
        return true
    }
}

func renderHachupingPreview(to path:String,time:Double,held:Bool=false)->Int32 {
    registerRettoFont();let layout=petLayout(scale:224/basePetWidth)
    let cases:[(PetState,DragRun?,String?,Int?)]=[(.idle,nil,nil,nil),(.running,nil,"mirror",nil),(.running,nil,"harp",nil),(.running,nil,"perfume",nil),(.running,nil,"bell",nil),(.running,nil,"puff",nil),(.waving,nil,nil,nil),(.jumping,nil,nil,nil),(.idle,.right,nil,nil),(.idle,.left,nil,nil),(.sleeping,nil,nil,nil),(.idle,nil,nil,4)]
    guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1344,pixelsHigh:1280,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let c=NSGraphicsContext(bitmapImageRep:b)else{return 1}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=c
    for(i,item)in cases.enumerated(){
        let v=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:HachupingSkin.placeholder,skin:.hachupingping,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=224/basePetWidth
        let data=Data("{\"state\":\"\(item.0.rawValue)\",\"sessionId\":\"fixture\"}".utf8)
        guard let payload=try? JSONDecoder().decode(StatePayload.self,from:data)else{return 1}
        v.apply(payload,state:item.0,sessionCount:1,attentionCount:0,isPinned:false)
        v.setDragRunForPreview(item.1);v.settleAnimations();v.setHachupingPreview(time:time,working:item.2,gaze:item.3,held:held)
        for dark in 0..<2 {
            let x=CGFloat(i%6*224),y=CGFloat((3-(dark*2+i/6))*320)
            (dark==0 ? NSColor.white:NSColor(calibratedWhite:0.14,alpha:1)).setFill();NSRect(x:x,y:y,width:224,height:320).fill()
            NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:224,height:320).clip();let a=NSAffineTransform();a.translateX(by:x-layout.petRect.minX,yBy:y-layout.petRect.minY);a.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
        }
    }
    NSGraphicsContext.restoreGraphicsState();guard let d=b.representation(using:.png,properties:[:])else{return 1}
    do{try d.write(to:URL(fileURLWithPath:path));return 0}catch{return 1}
}

func renderHachupingDragFit(to path:String,time:Double)->Int32 {
    registerRettoFont();let layout=petLayout(scale:224/basePetWidth)
    let cases:[DragRun?]=[nil,.right,.left]
    guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:960,pixelsHigh:720,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let c=NSGraphicsContext(bitmapImageRep:b)else{return 1}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=c
    for(i,drag)in cases.enumerated(){
        let v=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:HachupingSkin.placeholder,skin:.hachupingping,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=224/basePetWidth
        let p=try! JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"idle\",\"sessionId\":\"drag-size-fixture\"}".utf8))
        v.apply(p,state:.idle,sessionCount:1,attentionCount:0,isPinned:false);v.setDragRunForPreview(drag);v.settleAnimations();v.setHachupingPreview(time:time,working:nil,gaze:nil,held:false)
        for dark in 0..<2 {
            let x=CGFloat(i*320),y=CGFloat((1-dark)*360)
            (dark==0 ? NSColor.white:NSColor(calibratedWhite:0.14,alpha:1)).setFill();NSRect(x:x,y:y,width:320,height:360).fill()
            NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:320,height:360).clip();let a=NSAffineTransform();a.translateX(by:x+48-layout.petRect.minX,yBy:y+20-layout.petRect.minY);a.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
        }
    }
    NSGraphicsContext.restoreGraphicsState();guard let d=b.representation(using:.png,properties:[:])else{return 1}
    do{try d.write(to:URL(fileURLWithPath:path));return 0}catch{return 1}
}
