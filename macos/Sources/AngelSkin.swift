import AppKit
import Foundation

/// Approved full scenes sampled at their exact10/20Hz clocks. Character drawings hold for150/200/400ms;
/// effect samples continue during each hold. Never load/draw the old angel atlas too.
enum AngelSkin {
    struct Motion: Decodable {
        let samples: Int; let sampleMs:Double; let cycle: Double; let poseMs: Double; let drawings: Int
        let bodyScale: Double; let ground: Double
    }
    struct Manifest: Decodable { let sourceSize: [Int]; let sampleMs: Int; let states: [String:Motion] }
    static let root = Bundle.main.resourceURL!.appendingPathComponent("AngelFrames")
    static let manifest: Manifest? = {
        guard let d=try? Data(contentsOf:root.appendingPathComponent("manifest.json")) else{return nil}
        return try? JSONDecoder().decode(Manifest.self,from:d)
    }()
    static let available: Bool = {
        guard let m=manifest,m.sourceSize==[544,544],m.sampleMs==50,m.states.count==7 else{return false}
        for (key,value) in m.states {
            guard value.drawings==16,abs(Double(value.samples)*value.sampleMs/1000-value.cycle)<0.000001 else{return false}
            for i in 0..<value.samples where !FileManager.default.fileExists(atPath:root.appendingPathComponent(String(format:"%@/%03d.png",key,i)).path){return false}
        }
        return true
    }()
    static let cache = DecodedFrameCache.angel
    static func key(row:Int)->String? {
        switch row {case 0:return "idle";case 3:return "waving";case 4:return "jumping";case 5:return "failed";case 6:return "waiting";case 7,8:return "running";case 11:return "sleeping";default:return nil}
    }
    static func animation(_ a:Animation)->Animation {
        guard let k=key(row:a.row),let m=manifest?.states[k] else{return a}
        return Animation(row:a.row==8 ? 7:a.row,frames:16,interval:m.cycle/16,cycleLimit:a.cycleLimit,kicker:a.kicker,title:a.title,tone:a.tone)
    }
    static func sample(row:Int,time:Double)->Int {
        guard let k=key(row:row),let m=manifest?.states[k],time.isFinite else{return 0}
        return Int(floor(max(0,time).truncatingRemainder(dividingBy:m.cycle)/(m.sampleMs/1000)+1e-7))%m.samples
    }
    static func position(row:Int,time:Double)->(frame:Int,cycles:Int) {
        guard let k=key(row:row),let m=manifest?.states[k] else{return (0,0)}
        let t=max(0,time);return (Int(floor(t/(m.cycle/16)+1e-7))%16,Int(floor(t/m.cycle)))
    }
    /// Uniform display transform from main body landmarks, excluding wings/pets/FX.
    ///544px scene units correspond to448px original-body units, then bodyScale.
    static func rect(row:Int,in canvas:NSRect)->NSRect {
        guard let k=key(row:row),let m=manifest?.states[k] else{return canvas}
        let side=canvas.width*544/448*CGFloat(m.bodyScale)
        let ground=canvas.maxY-canvas.height*628/640
        return NSRect(x:canvas.midX-side/2,y:ground-side*(1-CGFloat(m.ground)/544),width:side,height:side)
    }
    static func windowSize(_ size:NSSize,scale:CGFloat)->NSSize {
        NSSize(width:max(size.width,basePetWidth*scale*1.30+12*scale),height:size.height)
    }
    @discardableResult static func draw(row:Int,time:Double,in canvas:NSRect)->Bool {
        guard available,let key=key(row:row) else{return false}
        let name=String(format:"%@/%03d.png",key,sample(row:row,time:time))
        guard let image=cache.image(at:root.appendingPathComponent(name)) else{return false}
        image.draw(in:rect(row:row,in:canvas),from:NSRect(origin:.zero,size:image.size),operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high]);return true
    }
    static func validate()->Bool {
        guard available,let m=manifest else{print("Angel resources unavailable",root.path,String(describing:manifest));return false}
        for (key,v) in m.states {
            let row=[0,3,4,5,6,7,11].first{self.key(row:$0)==key}!
            for i in 0..<v.samples {guard sample(row:row,time:Double(i)*v.sampleMs/1000)==i else{print("Sample mismatch",key,i,sample(row:row,time:Double(i)*v.sampleMs/1000));return false}}
            guard sample(row:row,time:v.cycle)==0,position(row:row,time:v.cycle+0.001).cycles==1 else{print("Cycle mismatch",key);return false}
            for scale in supportedScales {
                let canvas=NSRect(x:30,y:100,width:294*scale,height:420*scale);let fit=rect(row:row,in:canvas)
                guard abs(fit.width/fit.height-1)<0.000001,
                      abs(fit.maxY-fit.height*CGFloat(v.ground)/544-(canvas.maxY-canvas.height*628/640))<0.000001 else{return false}
                let size=windowSize(NSSize(width:306*scale,height:500*scale),scale:scale)
                guard size.width>=fit.width else{print("Overscan mismatch",key,scale,size,fit);return false}
            }
        }
        guard key(row:8)==key(row:7),key(row:1)==nil,key(row:9)==nil else{return false}
        print("PASS Angel:7 states,16 retained drawings each,10/20Hz scene/effect samples,exact2.4/3.2/6.4s clocks,body-derived uniform fit and support,overscan at7 scales; review aliases running; legacy drag retained")
        return true
    }
}

func renderAngelPreview(to path:String,time:Double)->Int32 {
    registerRettoFont();let l=petLayout(scale:224/basePetWidth)
    let cases:[PetState]=[.idle,.running,.waiting,.failed,.waving,.jumping,.sleeping,.review]
    guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1280,pixelsHigh:1360,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let c=NSGraphicsContext(bitmapImageRep:b)else{return 1}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=c
    for (i,state) in cases.enumerated() {
        let v=RettoView(frame:NSRect(x:0,y:0,width:320,height:l.windowSize.height),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=224/basePetWidth
        let data=Data("{\"state\":\"\(state.rawValue)\",\"sessionId\":\"angel-fixture\"}".utf8)
        guard let p=try? JSONDecoder().decode(StatePayload.self,from:data)else{return 1}
        v.apply(p,state:state,sessionCount:1,attentionCount:0,isPinned:false);v.settleAnimations();v.setAngelTimeForPreview(time)
        for dark in 0..<2 {
            let x=CGFloat(i%4*320),y=CGFloat((3-(dark*2+i/4))*340)
            (dark==0 ? NSColor.white:NSColor(calibratedRed:0.06,green:0.09,blue:0.16,alpha:1)).setFill();NSRect(x:x,y:y,width:320,height:340).fill()
            NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:320,height:340).clip();let tr=NSAffineTransform();tr.translateX(by:x,yBy:y-l.petRect.minY+10);tr.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
        }
    }
    NSGraphicsContext.restoreGraphicsState();guard let data=b.representation(using:.png,properties:[:])else{return 1}
    do{try data.write(to:URL(fileURLWithPath:path));return 0}catch{return 1}
}
