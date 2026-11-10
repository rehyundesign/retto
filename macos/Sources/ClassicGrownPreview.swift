import AppKit

/// Render the production RettoView path at 1x, including every packaged motion cell.
func renderClassicGrownPreview(to path: String) -> Int32 {
    _ = NSApplication.shared
    guard ClassicGrown.selfTest(),
          let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
          let atlas = NSImage(contentsOf: url) else { return 1 }
    let rows: [(Int, PetState, DragRun?)] = [
        (0,.idle,nil),(1,.idle,.right),(2,.idle,.left),(3,.waving,nil),
        (4,.jumping,nil),(5,.failed,nil),(6,.waiting,nil),(7,.running,nil),
        (8,.review,nil),(11,.sleeping,nil)
    ]
    let root = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let displayScale: CGFloat = 0.5
    let layout = petLayout(scale: displayScale)
    var count = 0
    for (row,state,drag) in rows {
        guard let motion = ClassicGrown.motion(row: row) else { return 1 }
        let view = RettoView(frame: NSRect(origin:.zero,size:layout.windowSize), spriteSheet: atlas,
                             skin:.classic, onOpenClaude:{_,_ in}, onOpenAttention:{_ in})
        view.petScale = displayScale
        let payload = try! JSONDecoder().decode(StatePayload.self,
            from: Data("{\"state\":\"\(state.rawValue)\",\"sessionId\":\"classic-grown-preview\",\"projectName\":\"Retto\"}".utf8))
        view.apply(payload,state:state,sessionCount:1,attentionCount:0,isPinned:false)
        view.setDragRunForPreview(drag)
        for i in motion.files.indices {
            view.setFrameForPreview(i)
            let image = NSImage(size: view.bounds.size)
            image.lockFocus(); NSColor.white.setFill(); view.bounds.fill(); view.draw(view.bounds); image.unlockFocus()
            guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),
                  let png=rep.representation(using:.png,properties:[:]) else { return 1 }
            do { try png.write(to:root.appendingPathComponent("row-\(row)-\(i).png")) } catch { return 1 }
            count += 1
        }
    }
    let transitions = RettoView(frame:NSRect(x:0,y:0,width:224,height:320),spriteSheet:atlas,skin:.classic,
                                onOpenClaude:{_,_ in},onOpenAttention:{_ in}).validateClassicGrownTransitions()
    print("Classic grown production renders: \(count), transitions: \(transitions)")
    return count == 153 && transitions ? 0 : 1
}
