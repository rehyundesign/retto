import AppKit
import Foundation

func renderChocolatHeartPreview(to path: String) -> Int32 {
    registerRettoFont()
    let scale: CGFloat = 224 / basePetWidth
    let layout = petLayout(scale: scale)
    let size = NSSize(width: 16*224, height: 10*2*320)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return 1 }
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    for i in 0..<10 {
        let state=PetState(rawValue:ChocolatHeart.names[i]) ?? .idle
        let view=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:ChocolatHeart.placeholder,skin:.chocolatHeart,onOpenClaude:{ _,_ in },onOpenAttention:{ _ in })
        view.petScale=scale
        let fixture="{\"state\":\"\(state.rawValue)\",\"sessionId\":\"chocolat-preview\",\"projectName\":\"Retto\"}".data(using:.utf8)!
        guard let payload=try? JSONDecoder().decode(StatePayload.self,from:fixture) else { return 1 }
        view.apply(payload,sessionCount:1,attentionCount:0,isPinned:false)
        let drag: DragRun?=i==8 ? .right : i==9 ? .left : nil
        view.setChocolatTimeForPreview(0,drag:drag);view.settleAnimations()
        for dark in 0..<2 { for frame in 0..<ChocolatHeart.counts[i] {
            let x=CGFloat(frame*224),y=size.height-CGFloat((i*2+dark+1)*320)
            (dark==0 ? NSColor.white:NSColor(calibratedWhite:0.14,alpha:1)).setFill();NSRect(x:x,y:y,width:224,height:320).fill()
            view.setFrameForPreview(frame);view.setChocolatTimeForPreview(Double(frame)*ChocolatHeart.intervals[i]/ChocolatHeart.speed,drag:drag)
            NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:224,height:320).clip()
            let transform=NSAffineTransform();transform.translateX(by:x-layout.petRect.minX,yBy:y-layout.petRect.minY);transform.concat();view.draw(view.bounds);NSGraphicsContext.restoreGraphicsState()
        } }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data=bitmap.representation(using:.png,properties:[:]) else { return 1 }
    do { try data.write(to:URL(fileURLWithPath:path)) } catch { return 1 };return 0
}
