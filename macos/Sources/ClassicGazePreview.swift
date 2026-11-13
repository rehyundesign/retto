import AppKit

func renderClassicGazePreview(to path: String) -> Int32 {
    _ = NSApplication.shared
    guard ClassicGrown.gazeSelfTest(),let url=Bundle.main.url(forResource:"spritesheet",withExtension:"webp"),let atlas=NSImage(contentsOf:url) else{return 1}
    let output=URL(fileURLWithPath:path)
    try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let scale:CGFloat=0.5,layout=petLayout(scale:0.5)
    var count=0
    for state in [PetState.idle,.running,.waving] {
        let view=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:atlas,skin:.classic,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
        view.petScale=scale
        let payload=try! JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"\(state.rawValue)\",\"sessionId\":\"classic-gaze-preview\",\"projectName\":\"Retto\"}".utf8))
        view.apply(payload,state:state,sessionCount:1,attentionCount:0,isPinned:false)
        for direction in 0..<16 {
            view.setGazeDirectionForPreview(direction)
            let image=NSImage(size:view.bounds.size);image.lockFocus();NSColor.white.setFill();view.bounds.fill();view.draw(view.bounds);image.unlockFocus()
            guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else{return 1}
            do{try png.write(to:output.appendingPathComponent("\(state.rawValue)-\(direction).png"))}catch{return 1}
            count+=1
        }
    }
    let test=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:atlas,skin:.classic,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
    test.petScale=scale
    let transitions=test.validateClassicGazeTransitions()
    print("Classic gaze production renders:\(count), transitions:\(transitions)")
    return count==48 && transitions ? 0:1
}
