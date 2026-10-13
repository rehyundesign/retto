import AppKit
import Foundation

enum MagicalHeartMotion {
    static let cycleSeconds: [Int: TimeInterval] = [
        0: 3.2, 1: 1.6, 2: 1.6, 3: 2.4, 4: 2.4,
        5: 3.2, 6: 3.2, 7: 2.4, 8: 3.2, 11: 6.4
    ]

    static func animation(_ original: Animation, columns: Int) -> Animation {
        guard columns == 16, let cycle = cycleSeconds[original.row] else { return original }
        return Animation(row: original.row, frames: 16, interval: cycle / 16,
                         cycleLimit: original.cycleLimit, kicker: original.kicker,
                         title: original.title, tone: original.tone)
    }

    /// 지연된 콜백 뒤에도 실제 경과 시간으로 포즈와 완료 횟수를 계산한다.
    static func position(elapsed: TimeInterval, frames: Int, interval: TimeInterval) -> (frame: Int, cycles: Int) {
        guard elapsed.isFinite, interval.isFinite, interval > 0, frames > 0 else { return (0, 0) }
        let ticks = floor(max(0, elapsed) / interval)
        return (Int(ticks.truncatingRemainder(dividingBy: Double(frames))),
                Int(min(floor(ticks / Double(frames)), Double(Int.max / 2))))
    }
}

enum MagicalHeartEffects {
    static func draw(state: PetState, drag: DragRun?, in rect: NSRect, time: TimeInterval, front: Bool) {
        let t = max(0, time)
        let unit = rect.width / 224
        let pink = NSColor(calibratedRed: 1, green: 0.40, blue: 0.65, alpha: 1)
        let gold = NSColor(calibratedRed: 1, green: 0.79, blue: 0.47, alpha: 1)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !front {
            guard drag == nil, state == .running || state == .waiting || state == .review else { return }
            let center = point(0.50, 0.30)
            let phase = CGFloat(t * .pi / 4)
            let radius = rect.width * (state == .running ? 0.39 : 0.32)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius * 0.23,
                                                 width: radius * 2, height: radius * 0.46))
            ring.lineWidth = 0.9 * unit
            pink.withAlphaComponent(0.12 + 0.06 * sin(phase)).setStroke()
            ring.stroke()
            for index in 0..<3 {
                let angle = phase + CGFloat(index) * .pi * 2 / 3
                sparkle(at: NSPoint(x: center.x + cos(angle) * radius,
                                    y: center.y + sin(angle) * radius * 0.23),
                        radius: 2.2 * unit, color: gold.withAlphaComponent(0.5))
            }
            return
        }

        // 입자는 서로 다른 위상으로 이동하고, 얼굴과 지지하는 발의 바깥을 통과한다.
        let sleeping = state == .sleeping
        let count = sleeping ? 3 : (drag == nil ? 6 : 5)
        let period: Double = sleeping ? 8 : (drag == nil ? 5.6 : 2.8)
        for index in 0..<count {
            let phase = (t / period + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
            let p = CGFloat(phase)
            let envelope = pow(sin(p * .pi), 2)
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            var x: CGFloat = side < 0 ? 0.09 : 0.91
            var y: CGFloat = 0.27 + p * 0.45
            if let drag {
                let direction: CGFloat = drag == .right ? 1 : -1
                x = 0.5 - direction * (0.25 + p * 0.19)
                y = 0.21 + CGFloat(index % 3) * 0.08 + sin(p * .pi) * 0.04
            } else if sleeping {
                x = 0.20 + CGFloat(index) * 0.27 + sin(p * .pi * 2) * 0.025
                y = 0.39 + p * 0.25
            } else {
                x += sin(p * .pi * 2 + CGFloat(index)) * 0.025
            }
            let color = (index.isMultiple(of: 2) ? pink : gold).withAlphaComponent(envelope * (sleeping ? 0.40 : 0.66))
            let radius = (2.1 + envelope * 1.4) * unit
            if !sleeping && drag == nil && (state == .waving || state == .waiting || state == .failed) && index.isMultiple(of: 2) {
                heart(at: point(x, y), radius: radius * 1.4, color: color)
            } else {
                sparkle(at: point(x, y), radius: radius, color: color)
            }
        }
    }

    private static func sparkle(at center: NSPoint, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            let r = index.isMultiple(of: 2) ? radius : radius * 0.27
            let point = NSPoint(x: center.x + sin(angle) * r, y: center.y + cos(angle) * r)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        color.setFill()
        path.fill()
    }

    private static func heart(at c: NSPoint, radius r: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x, y: c.y - r))
        path.curve(to: NSPoint(x: c.x, y: c.y + r * 0.38),
                   controlPoint1: NSPoint(x: c.x - r * 1.8, y: c.y + r * 0.15),
                   controlPoint2: NSPoint(x: c.x - r * 0.7, y: c.y + r * 1.6))
        path.curve(to: NSPoint(x: c.x, y: c.y - r),
                   controlPoint1: NSPoint(x: c.x + r * 0.7, y: c.y + r * 1.6),
                   controlPoint2: NSPoint(x: c.x + r * 1.8, y: c.y + r * 0.15))
        path.close()
        color.setFill()
        path.fill()
    }
}
