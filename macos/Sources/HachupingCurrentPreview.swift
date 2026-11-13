import AppKit
import Foundation

/// Render the actual RettoView with the approved mapping at224x320, not a web GIF.
func renderHachupingCurrent(to path:String,time:Double,held:Bool,dark:Bool)->Int32 {
    registerRettoFont();let layout=petLayout(scale:224/basePetWidth)
    let cases:[(String,PetState,DragRun?,String?,Int?)]=[
        ("IDLE",.idle,nil,nil,nil),("WAIT LIME",.waiting,nil,nil,nil),
        ("WORK MIRROR",.running,nil,"mirror",nil),("WORK POSIL",.running,nil,"perfume",nil),
        ("WORK BELL",.running,nil,"bell",nil),("WORK STAR",.running,nil,"puff",nil),
        ("FAILED",.failed,nil,nil,nil),("DONE",.waving,nil,nil,nil),
        ("CLICK",.jumping,nil,nil,nil),("RIGHT",.idle,.right,nil,nil),
        ("LEFT",.idle,.left,nil,nil),("SLEEP",.sleeping,nil,nil,nil),
        ("GAZE UP",.idle,nil,nil,0),("GAZE RIGHT",.idle,nil,nil,4),
        ("GAZE DOWN",.idle,nil,nil,8),("GAZE LEFT",.idle,nil,nil,12)]
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:896,pixelsHigh:1280,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap)else{return 1}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    for(i,item)in cases.enumerated(){
        let v=RettoView(frame:NSRect(origin:.zero,size:layout.windowSize),spriteSheet:HachupingSkin.placeholder,skin:.hachupingping,onOpenClaude:{_,_ in},onOpenAttention:{_ in});v.petScale=224/basePetWidth
        let p=try! JSONDecoder().decode(StatePayload.self,from:Data("{\"state\":\"\(item.1.rawValue)\",\"sessionId\":\"native-current\"}".utf8))
        v.apply(p,state:item.1,sessionCount:1,attentionCount:0,isPinned:false);v.setDragRunForPreview(item.2);v.settleAnimations();v.setHachupingPreview(time:time,working:item.3,gaze:item.4,held:held)
        let x=CGFloat(i%4*224),y=CGFloat((3-i/4)*320)
        (dark ? NSColor(calibratedWhite:0.14,alpha:1):NSColor.white).setFill();NSRect(x:x,y:y,width:224,height:320).fill()
        NSGraphicsContext.saveGraphicsState();NSRect(x:x,y:y,width:224,height:320).clip();let a=NSAffineTransform();a.translateX(by:x-layout.petRect.minX,yBy:y-layout.petRect.minY);a.concat();v.draw(v.bounds);NSGraphicsContext.restoreGraphicsState()
        (item.0 as NSString).draw(at:NSPoint(x:x+5,y:y+303),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:dark ? NSColor.white:NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState();guard let data=bitmap.representation(using:.png,properties:[:])else{return 1}
    do{try data.write(to:URL(fileURLWithPath:path));return 0}catch{return 1}
}
