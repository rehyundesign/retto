import AppKit
import Foundation

/// Small pose-linked highlights; the ambient raster layers keep their own clock.
enum AmuRanAccents {
    struct Spec: Decodable {
        let anchor: [Double]
        let mode: String
        let peak: Double
        let width: Double
        let strength: Double
    }
    private struct Settings: Decodable { let effects: [String: Spec] }
    private static let settings: Settings? = {
        guard let url = Bundle.main.url(forResource: "interaction", withExtension: "json", subdirectory: "AmuRanFrames"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }()
    static func draw(row: Int, poseTime: Double, gaze: Bool, in rect: NSRect) {
        guard !gaze, poseTime.isFinite, let spec = settings?.effects[String(row)],
              spec.anchor.count == 2, spec.strength > 0, spec.width > 0,
              let cycle = AmuRanMotion.cycles[row] else { return }
        let phase = (max(0, poseTime) / cycle).truncatingRemainder(dividingBy: 1)
        let difference = abs(phase - spec.peak), distance = min(difference, 1 - difference)
        let power = pow(max(0, 1 - distance / spec.width), 2) * spec.strength
        guard power >= 0.01 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.scaleX(by: rect.width / 448, yBy: -rect.height / 640)
        transform.concat()
        let x = spec.anchor[0], y = spec.anchor[1]
        func pink(_ alpha: Double) -> NSColor { NSColor(calibratedRed:1,green:82/255,blue:154/255,alpha:alpha) }
        let shadow = NSShadow(); shadow.shadowColor = pink(0.5 * power)
        shadow.shadowBlurRadius = spec.mode == "ring" ? 3 : 4; shadow.shadowOffset = .zero; shadow.set()
        if spec.mode == "ring" {
            for j in 0..<2 {
                let rx = 22 + 22 * power + Double(j) * 9, ry = 4 + 5 * power + Double(j) * 2
                pink(150/255 * power / Double(j+1)).setStroke()
                let ring = NSBezierPath(ovalIn:NSRect(x:x-rx,y:y-ry,width:rx*2,height:ry*2));ring.lineWidth=2;ring.stroke()
            }
        } else {
            for (radius,alpha) in [(18.0,45.0),(11.0,85.0),(4.0,200.0)] {
                pink(alpha/255 * power).setFill()
                NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2)).fill()
            }
            if spec.mode == "signal" {
                for j in 0..<2 {
                    let ring=NSBezierPath();ring.lineWidth=2;pink(130/255*power).setStroke()
                    ring.appendArc(withCenter:NSPoint(x:x,y:y),radius:15+Double(j)*9+power*4,startAngle:280,endAngle:435)
                    ring.stroke()
                }
            }
            for j in 0..<3 {
                let angle=Double(j-1)*0.8, radius=5+power*3
                let px=x+(x<224 ? -1.0 : 1.0)*cos(angle)*(12+15*power), py=y+sin(angle)*(12+15*power)
                let path=NSBezierPath()
                if spec.mode == "glint" {
                    NSColor(calibratedRed:1,green:224/255,blue:183/255,alpha:245/255*power).setFill()
                    path.move(to:NSPoint(x:px,y:py-radius));path.line(to:NSPoint(x:px+radius*0.45,y:py));path.line(to:NSPoint(x:px,y:py+radius));path.line(to:NSPoint(x:px-radius*0.45,y:py))
                } else {
                    pink(245/255*power).setFill()
                    for i in 0..<32 {
                        let a=Double(i)*2*Double.pi/32
                        let point=NSPoint(x:px+radius*pow(sin(a),3),y:py-radius*(13*cos(a)-5*cos(2*a)-2*cos(3*a)-cos(4*a))/16)
                        if i==0 { path.move(to:point) } else { path.line(to:point) }
                    }
                }
                path.close();path.fill()
            }
        }
        if spec.mode != "ring" {
            NSColor(calibratedRed:1,green:244/255,blue:250/255,alpha:230/255*min(1,power)).setFill()
            let core=NSBezierPath();core.move(to:NSPoint(x:x,y:y-5));core.line(to:NSPoint(x:x+2.5,y:y));core.line(to:NSPoint(x:x,y:y+5));core.line(to:NSPoint(x:x-2.5,y:y));core.close();core.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
