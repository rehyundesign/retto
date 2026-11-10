import AppKit
import Foundation

/// Optional additions. Existing seven AngelFrames states stay byte-identical.
enum AngelInteractions {
    struct Clip:Decodable {let samples:Int;let cycle:Double;let sampleMs:Double;let drawings:Int;let poseMs:Double}
    struct Anchor:Decodable {let tato:[Double];let melody:[Double];let star:[Double]}
    struct Gaze:Decodable {let count:Int;let samples:Int;let cycle:Double;let anchors:[Anchor]}
    struct Manifest:Decodable {let version:Int;let idle:Clip?;let flight:[String:Clip]?;let gaze:Gaze?}
    static let root=Bundle.main.resourceURL!.appendingPathComponent("AngelInteractions")
    static let manifest:Manifest?={guard let d=try? Data(contentsOf:root.appendingPathComponent("manifest.json"))else{return nil};return try? JSONDecoder().decode(Manifest.self,from:d)}()
    static func files(_ key:String,_ clip:Clip)->Bool {
        guard clip.drawings==16,clip.samples>0,abs(Double(clip.samples)*clip.sampleMs/1000-clip.cycle)<0.000001 else{return false}
        return (0..<clip.samples).allSatisfy{FileManager.default.fileExists(atPath:root.appendingPathComponent(String(format:"%@/%03d.png",key,$0)).path)}
    }
    static let hasIdle:Bool={guard let m=manifest?.idle else{return false};return files("idle-look",m)}()
    static let hasFlight:Bool={guard let f=manifest?.flight,let l=f["drag-left"],let r=f["drag-right"] else{return false};return files("drag-left",l)&&files("drag-right",r)}()
    static let hasGaze:Bool={guard let g=manifest?.gaze,g.count==16,g.anchors.count==16,g.samples==64 else{return false};return (0..<16).allSatisfy{FileManager.default.fileExists(atPath:root.appendingPathComponent(String(format:"gaze/%02d.png",$0)).path)} && (0..<g.samples).allSatisfy{FileManager.default.fileExists(atPath:root.appendingPathComponent(String(format:"gaze-back/%03d.png",$0)).path)}}()
    static let cache = DecodedFrameCache.angel
    struct IdleChoice {
        private(set) var cycle:Int?;private(set) var variant=0
        mutating func choose(cycle next:Int,picker:()->Int={Int.random(in:0...1)}) {
            guard cycle != next else{return};cycle=next;variant=AngelInteractions.hasIdle ? max(0,min(1,picker())):0
        }
        mutating func reset(){cycle=nil;variant=0}
        mutating func force(_ value:Int,cycle:Int){self.cycle=cycle;variant=value}
    }
    static func flightKey(_ row:Int)->String?{row==1 ? "drag-right":row==2 ? "drag-left":nil}
    static func animation(_ a:Animation)->Animation {
        guard hasFlight,let key=flightKey(a.row),let c=manifest?.flight?[key]else{return a}
        return Animation(row:a.row,frames:16,interval:c.poseMs/1000,cycleLimit:nil,kicker:a.kicker,title:a.title,tone:a.tone)
    }
    static func position(row:Int,time:Double)->(frame:Int,cycles:Int) {
        guard let key=flightKey(row),let c=manifest?.flight?[key]else{return (0,0)}
        let t=max(0,time),pose=c.poseMs/1000,cycle=Double(c.drawings)*pose
        return(Int(floor(t/pose+1e-7))%c.drawings,Int(floor(t/cycle)))
    }
    static func sample(_ c:Clip,time:Double)->Int{Int(floor(max(0,time).truncatingRemainder(dividingBy:c.cycle)/(c.sampleMs/1000)+1e-7))%c.samples}
    static func image(_ name:String)->NSImage? {
        cache.image(at:root.appendingPathComponent(name))
    }
    @discardableResult static func draw(key:String,time:Double,in canvas:NSRect)->Bool {
        let c:Clip?
        if key=="idle-look"{c=manifest?.idle}else{c=manifest?.flight?[key]}
        guard let c,let im=image(String(format:"%@/%03d.png",key,sample(c,time:time)))else{return false}
        im.draw(in:AngelSkin.rect(row:0,in:canvas),from:NSRect(origin:.zero,size:im.size),operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high]);return true
    }
    static func point(_ p:[Double],in rect:NSRect)->NSPoint{NSPoint(x:rect.minX+CGFloat(p[0])*rect.width/544,y:rect.maxY-CGFloat(p[1])*rect.height/544)}
    static func glyph(_ kind:String,at p:NSPoint,size:CGFloat,color:NSColor,alpha:CGFloat) {
        guard alpha>0 else{return};let path=NSBezierPath()
        if kind=="star" {
            for i in 0..<8 {let a=CGFloat(i) * .pi / 4;let r=size*(i%2==0 ? 0.48:0.13);let q=NSPoint(x:p.x+r*sin(a),y:p.y+r*cos(a));if i==0{path.move(to:q)}else{path.line(to:q)}};path.close()
        }else{
            for i in 0..<80 {let a=Double(i)*Double.pi*2/80;let x=16*pow(sin(a),3),y=13*cos(a)-5*cos(2*a)-2*cos(3*a)-cos(4*a);let q=NSPoint(x:p.x+CGFloat(x)*size*0.026,y:p.y+CGFloat(y)*size*0.026);if i==0{path.move(to:q)}else{path.line(to:q)}};path.close()
        }
        NSGraphicsContext.saveGraphicsState();let shadow=NSShadow();shadow.shadowColor=color.withAlphaComponent(alpha*0.4);shadow.shadowBlurRadius=size*0.25;shadow.shadowOffset = .zero;shadow.set();color.withAlphaComponent(alpha).setFill();path.fill();NSGraphicsContext.restoreGraphicsState()
    }
    @discardableResult static func drawGaze(direction:Int,time:Double,in canvas:NSRect)->Bool {
        guard hasGaze,let g=manifest?.gaze else{return false};let d=max(0,min(15,direction));let rect=AngelSkin.rect(row:0,in:canvas);let s=Int(floor(max(0,time).truncatingRemainder(dividingBy:g.cycle)/0.05+1e-7))%g.samples
        if let back=image(String(format:"gaze-back/%03d.png",s)){back.draw(in:rect,from:NSRect(origin:.zero,size:back.size),operation:.sourceOver,fraction:1,respectFlipped:false,hints:nil)}
        let anchor=g.anchors[d]
        // Magic is behind characters: no iris, cheek or holding-paw recolouring.
        for actor in 0..<2 {
            let root=actor==0 ? anchor.tato:anchor.melody
            let color=actor==0 ? NSColor(calibratedRed:0.4,green:0.79,blue:1,alpha:1):NSColor(calibratedRed:1,green:0.43,blue:0.56,alpha:1)
            for j in 0..<3 {
                let q=(max(0,time)+Double(j)*0.15).truncatingRemainder(dividingBy:0.8)/0.8
                let p=[root[0]+(actor==0 ? -8:8)*q,root[1]+6+28*q]
                glyph(actor==0 ? "star":"heart",at:point(p,in:rect),size:rect.width/544*(actor==0 ? 16:14),color:color,alpha:CGFloat(0.82*pow(sin(Double.pi*q),1.2)))
            }
        }
        guard let char=image(String(format:"gaze/%02d.png",d))else{return false}
        char.draw(in:rect,from:NSRect(origin:.zero,size:char.size),operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high]);return true
    }
    static func validate(requireAll:Bool=true)->Bool {
        guard hasIdle,let c=manifest?.idle,abs(c.cycle-3.2)<0.000001 else{print("Idle variant missing");return false}
        var choice=IdleChoice();choice.choose(cycle:0,picker:{1});for _ in 0..<100{choice.choose(cycle:0,picker:{0});guard choice.variant==1 else{return false}};choice.choose(cycle:1,picker:{0});guard choice.variant==0 else{return false};choice.choose(cycle:2,picker:{1});guard choice.variant==1 else{return false}
        if requireAll {
            guard hasFlight,hasGaze,let f=manifest?.flight else{print("Incomplete requested interactions",hasFlight,hasGaze);return false}
            for row in [1,2] {
                guard let key=flightKey(row),let v=f[key],v.drawings==16,abs(v.poseMs-100)<0.000001 else{return false}
                for i in 0..<v.samples{guard sample(v,time:Double(i)*v.sampleMs/1000)==i else{return false}}
                guard position(row:row,time:1.601).cycles==1 else{return false}
            }
        }
        print("PASS Angel interactions: stable whole-cycle idle random, left/right16-pose flight1.6s with independent3.2s FX,16 full-body cursor directions; original7states preserved")
        return true
    }
}

func renderAngelInteractions(to directory:String)->Int32 {
    registerRettoFont();let dir=URL(fileURLWithPath:directory)
    do{try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}catch{return 1}
    for group in ["gaze","drag-left","drag-right","idle"] {
        let count=group=="idle" ? 2:16
        for i in 0..<count {
            for phase in [0,1] {
                let time=Double(i)*0.1+Double(phase)*0.45
                let l=petLayout(scale:224/basePetWidth)
                let v=RettoView(frame:NSRect(x:0,y:0,width:320,height:l.windowSize.height),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=224/basePetWidth
                guard let p=try? JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"idle\",\"sessionId\":\"angel-render\"}".utf8))else{return 1}
                v.apply(p,state:.idle,sessionCount:1,attentionCount:0,isPinned:false);v.settleAnimations()
                if group=="gaze"{v.setGazeDirectionForPreview(i)}
                if group=="drag-left" || group=="drag-right"{v.setDragRunForPreview(group=="drag-left" ? .left:.right)}
                if group=="idle"{v.setAngelIdleVariantForPreview(i,time:time)}else{v.setAngelTimeForPreview(time)}
                guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:320,pixelsHigh:340,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let c=NSGraphicsContext(bitmapImageRep:b)else{return 1}
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=c
                NSColor(calibratedRed:0.06,green:0.09,blue:0.16,alpha:1).setFill();NSRect(x:0,y:0,width:320,height:340).fill()
                let tr=NSAffineTransform();tr.translateX(by:0,yBy:-l.petRect.minY+10);tr.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
                guard let data=b.representation(using:.png,properties:[:])else{return 1}
                do{try data.write(to:dir.appendingPathComponent(String(format:"%@-%02d-%d.png",group,i,phase)))}catch{return 1}
            }
        }
    }
    return 0
}
