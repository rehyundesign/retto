import AppKit
import Foundation

// 승인한 festive-effects.mjs의 좌표·시간을 AppKit에서 그린다. 캐릭터 타이머와 분리한다.
func drawChristmasEffects(state: PetState, drag: DragRun?, gaze: Bool, in rect: NSRect,
                          time: TimeInterval, frame: Int, front: Bool) {
    let id = drag != nil ? "move" : gaze ? "idle" : state.rawValue
    let periods: [String: Double] = ["idle":4,"move":0.68,"running":3,"review":2,"waiting":1.86,
                                    "failed":3,"jumping":0.75,"sleeping":5,"waving":2.2]
    guard let period = Christmas16Timing.effectPeriod(id) ?? periods[id] else { return }
    let unit: (CGFloat) -> CGFloat = { $0 - floor($0) }
    let p = unit(CGFloat(time / period)), phase = p * .pi * 2
    let colors = [hexColor(0xd7354d), hexColor(0x287752), hexColor(0xedba58)]
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.maxY)
    transform.scaleX(by: rect.width / 448, yBy: -rect.height / 640)
    transform.concat()
    if drag == .left { let mirror = NSAffineTransform(); mirror.translateX(by:448,yBy:0); mirror.scaleX(by:-1,yBy:1); mirror.concat() }
    func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat, _ color: NSColor = hexColor(0xffc85f)) {
        for (radius,alpha,c) in [(r,a*0.16,color),(r*0.55,a*0.27,color),(r*0.18,a*0.8,hexColor(0xfff2b9))] {
            c.withAlphaComponent(alpha).setFill(); NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2)).fill()
        }
    }
    func glint(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat, _ angle: CGFloat = 0) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let tr=NSAffineTransform();tr.translateX(by:x,yBy:y);tr.rotate(byDegrees:angle);tr.concat()
        let path=NSBezierPath();path.move(to:NSPoint(x:0,y:-r))
        for (end,control) in [(NSPoint(x:r,y:0),NSPoint(x:r*0.2,y:-r*0.2)),(NSPoint(x:0,y:r),NSPoint(x:r*0.2,y:r*0.2)),(NSPoint(x:-r,y:0),NSPoint(x:-r*0.2,y:r*0.2)),(NSPoint(x:0,y:-r),NSPoint(x:-r*0.2,y:-r*0.2))] {
            let start=path.currentPoint
            path.curve(to:end,controlPoint1:NSPoint(x:start.x+(control.x-start.x)*2/3,y:start.y+(control.y-start.y)*2/3),controlPoint2:NSPoint(x:end.x+(control.x-end.x)*2/3,y:end.y+(control.y-end.y)*2/3))
        }
        path.close();hexColor(0xffdc75).withAlphaComponent(a).setFill();path.fill();hexColor(0xc99438).withAlphaComponent(a).setStroke();path.lineWidth=0.8;path.stroke()
    }
    func snow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat, _ angle: CGFloat) {
        NSGraphicsContext.saveGraphicsState();defer { NSGraphicsContext.restoreGraphicsState() }
        let tr=NSAffineTransform();tr.translateX(by:x,yBy:y);tr.rotate(byDegrees:angle);tr.concat()
        hexColor(0x83b9cc).withAlphaComponent(a).setStroke()
        for degrees: CGFloat in [0,60,120] {
            NSGraphicsContext.saveGraphicsState();let rot=NSAffineTransform();rot.rotate(byDegrees:degrees);rot.concat()
            let path=NSBezierPath();path.lineWidth=1.5;path.lineCapStyle = .round
            path.move(to:NSPoint(x:-r,y:0));path.line(to:NSPoint(x:r,y:0))
            for sign: CGFloat in [-1,1] { path.move(to:NSPoint(x:sign*r*0.62,y:-r*0.28));path.line(to:NSPoint(x:sign*r*0.37,y:0));path.line(to:NSPoint(x:sign*r*0.62,y:r*0.28)) }
            path.stroke();NSGraphicsContext.restoreGraphicsState()
        }
    }
    if id == "idle" {
        if !front { for i in 0..<6 { let q=unit(p+CGFloat(i)/6),x:CGFloat=i%2 == 1 ? 414:32; snow(x+9*sin(phase+CGFloat(i)),165+q*430,7+2*CGFloat(i%2),sin(q * .pi)*0.8,phase*25+CGFloat(i*30)) } }
        else { glint(36,568+12*sin(phase),8,0.25+0.5*(0.5+0.5*sin(phase*2)));glint(412,299+18*cos(phase),8,0.2+0.65*(0.5+0.5*cos(phase))) }
    }
    if id == "move" {
        for i in 0..<9 { let q=unit(p+CGFloat(i)/9),x=145-118*q,a=sin(q * .pi)*0.8
            if !front { snow(x,595+20*sin(q * .pi+CGFloat(i)*0.8),5+4*q,a,phase*30+CGFloat(i*30)) }
            else if i%3 == 0 { glint(x,617-12*q,5,a) }
        }
        if !front { let path=NSBezierPath();path.move(to:NSPoint(x:25,y:592));path.curve(to:NSPoint(x:109,y:587),controlPoint1:NSPoint(x:54,y:580+8*sin(phase)),controlPoint2:NSPoint(x:83,y:580+8*sin(phase)));path.lineWidth=2;path.setLineDash([5,11],count:2,phase:-p*32);hexColor(0xacd2df).withAlphaComponent(0.55).setStroke();path.stroke() }
    }
    if id == "running" && front {
        for i in 0..<7 { let a=phase+CGFloat(i) * .pi*2/7;glint(210+170*cos(a),536+38*sin(a),7+3*(0.5+0.5*sin(a)),0.3+0.6*(0.5+0.5*sin(a)),a*30) }
        let ring=NSBezierPath(ovalIn:NSRect(x:45,y:498,width:330,height:76));ring.lineWidth=2;ring.setLineDash([8,22],count:2,phase:-p*60);hexColor(0xdfb74e).withAlphaComponent(0.65).setStroke();ring.stroke()
        for i in 0..<3 { let q=unit(p+CGFloat(i)/3);glint(320+45*q,553-115*q,8,sin(q * .pi)*0.9,phase*40) }
        glow(207,536,18,0.4+0.4*pow(sin(phase),2))
    }
    if id == "review" {
        let anchor = Christmas16Attachments.points(id, frame: frame)?.first ?? [77, 494]
        let cx = anchor[0], cy = anchor[1]
        if !front { glow(cx,cy,46,0.45+0.45*pow(sin(phase),2));for i in 0..<5 {let a=phase+CGFloat(i) * .pi*2/5;glint(cx+37*cos(a),cy+37*sin(a),7,0.65,a*25)} }
        else { for i in 0..<6 {let a=phase/2+CGFloat(i) * .pi*2/6,r=29+7*sin(phase);let path=NSBezierPath();path.move(to:NSPoint(x:cx+cos(a)*r,y:cy+sin(a)*r));path.line(to:NSPoint(x:cx+cos(a)*(r+9),y:cy+sin(a)*(r+9)));path.lineWidth=2;hexColor(0xdfaa37).withAlphaComponent(0.35+0.5*pow(sin(phase),2)).setStroke();path.stroke()} }
    }
    if id == "waiting" {
        let anchor = Christmas16Attachments.points(id, frame: frame)?.first ?? [329, 438]
        let cx = anchor[0], cy = anchor[1]
        if !front { glow(cx,cy,29,0.35+0.5*pow(sin(phase),2)) }
        else {
            for i in 0..<3 {let q=unit(p+CGFloat(i)/3),r=12+38*q,path=NSBezierPath();for j in 0...16 {let a = -0.86+CGFloat(j)*1.72/16,point=NSPoint(x:cx+r*cos(a),y:cy+r*sin(a));if j == 0 {path.move(to:point)} else {path.line(to:point)}};path.lineWidth=3.4-1.4*q;hexColor(0xd79c32).withAlphaComponent(0.8*(1-q)).setStroke();path.stroke()}
            let q=unit(p+0.3),x=392+6*sin(phase),y=427-58*q,note=NSBezierPath();note.move(to:NSPoint(x:x,y:y));note.line(to:NSPoint(x:x,y:y-17));note.line(to:NSPoint(x:x+12,y:y-20));note.line(to:NSPoint(x:x+12,y:y-6));note.lineWidth=3;hexColor(0xc89332).withAlphaComponent(sin(q * .pi)).setStroke();note.stroke();hexColor(0xc89332).withAlphaComponent(sin(q * .pi)).setFill();NSBezierPath(ovalIn:NSRect(x:x-7,y:y-2,width:10,height:6)).fill();NSBezierPath(ovalIn:NSRect(x:x+5,y:y-8,width:10,height:6)).fill()
        }
    }
    if id == "failed" {
        let bulbs = Christmas16Attachments.points(id, frame: frame) ?? [[126,593],[173,608],[195,615],[217,608],[269,597]]
        if front { for (i,b) in bulbs.enumerated() {glow(b[0],b[1],10,0.15+0.65*pow(0.5+0.5*sin(phase-CGFloat(i)*1.2),3),colors[i%3])};let q=unit(p+0.2);glint(315+18*q,581-67*q,7,sin(q * .pi)*0.65,phase*30) }
        else { for i in 0..<3 {let q=unit(p+CGFloat(i)/3);snow(405+5*sin(phase+CGFloat(i)),535+74*q,6,sin(q * .pi)*0.55,phase*12)} }
    }
    if id == "jumping" {
        if !front {let r=24+160*p,h=5+8*p,ring=NSBezierPath(ovalIn:NSRect(x:205-r,y:612-h,width:r*2,height:h*2));ring.lineWidth=4-2*p;hexColor(0xdfb85a).withAlphaComponent(sin(p * .pi)*0.7).setStroke();ring.stroke()}
        for i in 0..<12 {let q=unit(p+CGFloat(i)*0.037),side:CGFloat=i%2 == 1 ? -1:1,x=205+side*(50+q*130),y=593-200*sin(q * .pi),a=sin(q * .pi)*0.9
            if !front && i%3 == 0 {snow(x,y,9,a,phase*50+CGFloat(i*30))}
            if front && i%3 != 0 {NSGraphicsContext.saveGraphicsState();let tr=NSAffineTransform();tr.translateX(by:x+3,yBy:y+6);tr.rotate(byDegrees:phase*75+CGFloat(i*40));tr.concat();colors[i%3].withAlphaComponent(a).setFill();NSBezierPath(roundedRect:NSRect(x:-3,y:-6,width:6,height:12),xRadius:1,yRadius:1).fill();NSGraphicsContext.restoreGraphicsState()}
        }
    }
    if id == "sleeping" {
        if !front {let x=285+9*sin(phase),y=392+7*cos(phase);glow(x,y,27,0.3+0.25*(0.5+0.5*sin(phase)));let moon=NSBezierPath();moon.move(to:NSPoint(x:x,y:y-16));moon.curve(to:NSPoint(x:x+13,y:y+13),controlPoint1:NSPoint(x:x-28,y:y-10),controlPoint2:NSPoint(x:x-22,y:y+27));moon.curve(to:NSPoint(x:x,y:y-16),controlPoint1:NSPoint(x:x-4,y:y+6),controlPoint2:NSPoint(x:x-6,y:y-5));moon.close();hexColor(0xeac36e).withAlphaComponent(0.85).setFill();moon.fill();for i in 0..<4 {let q=unit(p+CGFloat(i)/4);snow(174+CGFloat(i*58)+10*sin(phase+CGFloat(i)),353+82*q,6+2*CGFloat(i%2),sin(q * .pi)*0.65,phase*12+CGFloat(i*30))} }
        else {glint(403,452+12*sin(phase),7,0.3+0.3*pow(sin(phase),2))}
    }
    if id == "waving" {
        let paths: [(CGFloat,CGFloat,CGFloat,CGFloat,Bool)] = [(408,58,38,218,false),(420,150,390,574,true),(110,80,28,568,false)]
        for (i, track) in paths.enumerated() {
            let (sx,sy,ex,ey,isFront) = track
            guard isFront == front else { continue }
            let q=unit(p+CGFloat(i)*0.37),dx=ex-sx,dy=ey-sy,length=hypot(dx,dy),ux=dx/length,uy=dy/length
            let x=sx+dx*q,y=sy+dy*q,a=pow(sin(q * .pi),0.8)*0.95
            for (tailLength,width,opacity,color): (CGFloat,CGFloat,CGFloat,UInt32) in [(86,9,0.08,0xefb846),(68,4,0.28,0xe6b34c),(45,1.8,0.85,0xf5cf79)] {
                let visibleLength=min(tailLength,length*q)
                let trail=NSBezierPath();trail.move(to:NSPoint(x:x-ux*visibleLength,y:y-uy*visibleLength));trail.line(to:NSPoint(x:x,y:y));trail.lineWidth=width;trail.lineCapStyle = .round
                hexColor(color).withAlphaComponent(a*opacity).setStroke();trail.stroke()
            }
            for k in 1...4 {let offset=min(CGFloat(k*21),length*q);glint(x-ux*offset+(k%2 == 1 ? 3:-3),y-uy*offset,3.5-CGFloat(k)*0.45,a*(1-CGFloat(k)/5)*0.65)}
            glow(x,y,16,a)
            let star=NSBezierPath()
            for point in 0..<10 {let angle = -CGFloat.pi/2+CGFloat(point)*CGFloat.pi/5,r:CGFloat=point%2 == 1 ? 4:9,vertex=NSPoint(x:x+cos(angle)*r,y:y+sin(angle)*r);if point == 0 {star.move(to:vertex)} else {star.line(to:vertex)}}
            star.close();hexColor(0xffe39a).withAlphaComponent(a).setFill();star.fill();hexColor(0xc99438).withAlphaComponent(a).setStroke();star.lineWidth=1;star.stroke()
        }
    }
}

/// 캐릭터 프레임을 고정해도 모든 상태의 이펙트가 시간에 따라 바뀌어야 한다.
func christmasEffectsSelfTest() -> Bool {
    guard let url = Bundle.main.url(forResource: PetSkin.christmas.resourceName, withExtension: "webp"),
          let sheet = NSImage(contentsOf: url),
          SpriteSheetLayout.forImage(size: sheet.size) == .retto16 else { return false }
    func pixels(_ state: PetState, _ drag: DragRun?, _ gaze: Bool, _ time: TimeInterval) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 448, pixelsHigh: 640,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 448 * 4, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap), let bytes = bitmap.bitmapData else { return nil }
        memset(bytes, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for front in [false, true] {
            drawChristmasEffects(state: state, drag: drag, gaze: gaze,
                in: NSRect(x: 0, y: 0, width: 448, height: 640), time: time, frame: 0, front: front)
        }
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    let attachmentOK = ["review", "waiting", "failed"].allSatisfy { id in
        guard let frames = Christmas16Attachments.values[id], frames.count == 16 else { return false }
        return frames.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.count == 2 && $0[0] >= 0 && $0[0] < 448 && $0[1] >= 0 && $0[1] < 640 } }
    }
    guard attachmentOK else { return false }
    let samples = PetState.allCases.map { ($0, Optional<DragRun>.none, false) }
        + [(.idle, .right, false), (.idle, .left, false), (.idle, nil, true)]
    return samples.allSatisfy { state, drag, gaze in
        guard let first = pixels(state, drag, gaze, 0), let next = pixels(state, drag, gaze, 0.37) else { return false }
        return first != next
    }
}

/// Web과 AppKit이 동일한 프레임별 소품 위치를 사용한다.
private enum Christmas16Attachments {
    static let values: [String: [[[CGFloat]]]] = {
        guard let url = Bundle.main.url(forResource: "christmas-16-attachments", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) else { return [:] }
        return decoded.mapValues { $0.map { $0.map { $0.map { CGFloat($0) } } } }
    }()
    static func points(_ id: String, frame: Int) -> [[CGFloat]]? {
        guard let frames = values[id], frames.indices.contains(frame), !frames[frame].isEmpty else { return nil }
        return frames[frame]
    }
}
