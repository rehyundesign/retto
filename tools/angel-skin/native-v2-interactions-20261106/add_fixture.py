from pathlib import Path
R=Path(__file__).resolve().parent;D=R/'build/Sources';p=D/'PetView.swift';s=p.read_text();at='    private func playReaction() {';assert s.count(at)==1
s=s.replace(at,'''    func validateAngelInteractions()->Bool {
        guard AngelInteractions.validate() else{return false}
        guard let p=try? JSONDecoder().decode(StatePayload.self,from:Data("{\\"state\\":\\"idle\\",\\"sessionId\\":\\"angel-interaction-fixture\\"}".utf8))else{return false}
        apply(p,state:.idle,sessionCount:1,attentionCount:0,isPinned:false)
        for d in 0..<16 {
            clearGaze()
            let pivot=AngelInteractions.point([255,215],in:AngelSkin.rect(row:0,in:layout.petRect))
            let a=Double(d)*Double.pi/8
            updateAngelGaze(at:NSPoint(x:pivot.x+CGFloat(sin(a))*200,y:pivot.y+CGFloat(cos(a))*200))
            guard lookDirection==d,hasActiveGaze else{print("Cursor sector failure",d,lookDirection as Any);return false}
        }
        RunLoop.main.run(until:Date(timeIntervalSinceNow:gazeHoldDuration+0.15))
        guard lookDirection==nil,currentAnimation?.row==0,frameIndex<2 else{print("Gaze did not return to idle start");return false}
        for state in PetState.allCases where state != .idle {
            apply(p,state:state,sessionCount:1,attentionCount:0,isPinned:false)
            updateAngelGaze(at:NSPoint(x:1000,y:1000));guard !hasActiveGaze else{return false}
        }
        apply(p,state:.running,sessionCount:1,attentionCount:0,isPinned:false)
        for d in [DragRun.left,.right] {
            setDragRunForPreview(d)
            guard currentAnimation?.frames==16,currentAnimation?.interval==0.1,!allowsGaze else{return false}
            angelEpoch=ProcessInfo.processInfo.systemUptime-1.601;advanceFrame()
            guard frameIndex==0,completedCycles==1 else{print("Flight pose cadence mismatch");return false}
        }
        setDragRunForPreview(nil)
        guard currentAnimation?.row==7 || currentAnimation?.row==8 else{return false}
        print("PASS actual Angel cursor16sectors/hold/reset, working-state isolation, both16-pose airborne drag directions and return")
        return true
    }
''' + at)
p.write_text(s)
p=D/'main.swift';s=p.read_text();at='if CommandLine.arguments.contains("--angel-interactions-self-test")';s=s.replace(at,'''if CommandLine.arguments.contains("--angel-interactions-state-test") {
 let v=RettoView(frame:NSRect(x:0,y:0,width:400,height:500),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
 exit(v.validateAngelInteractions() ? 0:1)
}
if let i=CommandLine.arguments.firstIndex(of:"--render-angel-interactions"),i+1<CommandLine.arguments.count {exit(renderAngelInteractions(to:CommandLine.arguments[i+1]))}
''' + at,1);p.write_text(s)
p=D/'AngelInteractions.swift';s=p.read_text();fixture='''
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
                guard let p=try? JSONDecoder().decode(StatePayload.self,from:Data("{\\"state\\":\\"idle\\",\\"sessionId\\":\\"angel-render\\"}".utf8))else{return 1}
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
'''
if 'func renderAngelInteractions(to directory:String)' not in s:s+=fixture
p.write_text(s);(R/'AngelInteractions.swift').write_text(s)
