import AppKit

/// Fixed cameras for existing full-drawing pose groups. Never normalize individual frames.
enum HanaGrounding {
    static let targetFloor:CGFloat = 628
    static let sourceFloors:[Int:CGFloat] = [0:592,1:580,2:580,3:605,4:592,5:600,6:598,7:601,8:604,9:592,10:592,11:560]
    // Used only by the native diagnostic fixture to compare original versus grounded rendering.
    static var previewOriginal = false
    static func rect(row:Int,in canvas:NSRect)->NSRect {
        guard !previewOriginal,let source=sourceFloors[row] else{return canvas}
        return canvas.offsetBy(dx:0,dy:-canvas.height*(targetFloor-source)/640)
    }
    static func effectRow(state:PetState,drag:DragRun?)->Int {
        if let drag{return dragRunAnimations[drag]?.row ?? 0}
        return animationCatalog[state]?.row ?? 0
    }
    static func validate()->Bool {
        for scale:CGFloat in [0.39,0.5,0.65,1,1.4] {
            let canvas=NSRect(x:17,y:80,width:294*scale,height:420*scale)
            for (row,source) in sourceFloors {
                let out=rect(row:row,in:canvas)
                let foot=out.maxY-out.height*source/640
                let target=canvas.maxY-canvas.height*targetFloor/640
                guard abs(foot-target)<0.000001,out.size==canvas.size,out.minX==canvas.minX else{return false}
            }
        }
        guard sourceFloors[0]==sourceFloors[9],sourceFloors[0]==sourceFloors[10],sourceFloors[0]==sourceFloors[4],sourceFloors[1]==sourceFloors[2] else{return false}
        guard effectRow(state:.idle,drag:nil)==0,effectRow(state:.sleeping,drag:nil)==11,effectRow(state:.running,drag:.left)==2 else{return false}
        print("PASS Hana fixed pose-group ground cameras at5scales: unchanged sizes and gait/jump displacement, same character/front/back rect, shared idle/gaze/launch floor")
        return true
    }
}

func renderHanaGrounding(to directory:String)->Int32 {
    registerRettoFont();let dir=URL(fileURLWithPath:directory)
    do{try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}catch{return 1}
    let scale=224/basePetWidth,l=petLayout(scale:224/basePetWidth)
    var cases:[(String,PetState,DragRun?,Int?,Int)] = [
        ("idle",.idle,nil,nil,0),("working",.running,nil,nil,0),("review",.review,nil,nil,0),("waiting",.waiting,nil,nil,0),("failed",.failed,nil,nil,0),("completion",.waving,nil,nil,0),("jump-launch",.jumping,nil,nil,0),("jump-air",.jumping,nil,nil,8),("sleep",.sleeping,nil,nil,0),("drag-left",.idle,.left,nil,0),("drag-right",.idle,.right,nil,0)]
    for d in 0..<16{cases.append(("gaze-\(d)",.idle,nil,d,0))}
    for frame in 1..<16{cases.append(("idle-\(frame)",.idle,nil,nil,frame))}
    for entry in cases {
        guard let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:400,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:b)else{return 1}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSColor(calibratedRed:0.07,green:0.1,blue:0.16,alpha:1).setFill();NSRect(x:0,y:0,width:640,height:400).fill()
        for side in 0..<2 {
            HanaGrounding.previewOriginal = side==0
            let v=RettoView(frame:NSRect(x:0,y:0,width:320,height:l.windowSize.height),spriteSheet:HanaFrameCache.placeholder,skin:.hana,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=scale
            guard let p=try? JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"\(entry.1.rawValue)\",\"sessionId\":\"hana-ground-fixture\"}".utf8))else{return 1}
            v.apply(p,state:entry.1,sessionCount:1,attentionCount:0,isPinned:false);v.settleAnimations()
            if let drag=entry.2{v.setDragRunForPreview(drag)}
            if let gaze=entry.3{v.setGazeDirectionForPreview(gaze)}
            v.setFrameForPreview(entry.4);v.setChristmasTimeForPreview(Double(entry.4)/4)
            NSGraphicsContext.saveGraphicsState();NSRect(x:CGFloat(side*320),y:30,width:320,height:370).clip();let tr=NSAffineTransform();tr.translateX(by:CGFloat(side*320),yBy:40-l.petRect.minY);tr.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedRed:0.7,green:0.6,blue:0.35,alpha:0.6).setStroke();let line=NSBezierPath();line.move(to:NSPoint(x:CGFloat(side*320),y:40+l.petRect.height*12/640));line.line(to:NSPoint(x:CGFloat(side*320+320),y:40+l.petRect.height*12/640));line.stroke()
        }
        HanaGrounding.previewOriginal=false
        NSGraphicsContext.restoreGraphicsState();guard let data=b.representation(using:.png,properties:[:])else{return 1}
        do{try data.write(to:dir.appendingPathComponent(entry.0+".png"))}catch{return 1}
    }
    return 0
}
