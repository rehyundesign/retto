import AppKit
import Foundation

enum JeanneMotion {
    static let cycles: [Int: Double] = [0: 3.2, 1: 1.6, 2: 1.6, 3: 2.4, 4: 2.4,
                                       5: 3.2, 6: 3.2, 7: 2.4, 8: 3.2, 11: 6.4]
    static func animation(_ original: Animation) -> Animation {
        Animation(row: original.row, frames: 16, interval: (cycles[original.row] ?? 3.2) / 16,
                  cycleLimit: original.cycleLimit, kicker: original.kicker,
                  title: original.title, tone: original.tone)
    }
    static func position(elapsed: TimeInterval, interval: TimeInterval) -> (frame: Int, cycles: Int) {
        let tick = Int(max(0, elapsed) / interval)
        return (tick % 16, tick / 16)
    }
    static func id(state: PetState, drag: DragRun?) -> String {
        if let drag { return drag == .right ? "drag-right" : "drag-left" }
        return state.rawValue
    }
}

enum JeanneFrames {
    static var hasAllFrames: Bool {
        for row in JeanneMotion.cycles.keys {
            for frame in 0..<16 {
                if Bundle.main.url(forResource: "character-\(row)-\(frame)", withExtension: "png", subdirectory: "JeanneFrames") == nil { return false }
            }
        }
        return (0..<16).allSatisfy {
            Bundle.main.url(forResource: "gaze-\($0)", withExtension: "png", subdirectory: "JeanneFrames") != nil
        }
    }
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 56 * 1024 * 1024
        return cache
    }()
    static var placeholder: NSImage { NSImage(size: NSSize(width: 7168, height: 7680)) }
    static func image(row: Int, frame: Int) -> NSImage? {
        let key = row == 9 || row == 10 ? "gaze-\((row - 9) * 8 + frame)" : "character-\(row)-\(frame)"
        if let image = cache.object(forKey: key as NSString) { return image }
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "JeanneFrames"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4)
        return image
    }
    static func draw(row: Int, frame: Int, in rect: NSRect) -> Bool {
        guard let image = image(row: row, frame: frame) else { return false }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        return true
    }
}

func runJeanneResourceSelfTest() -> Int32 {
    guard JeanneFrames.hasAllFrames else { print("{\"ok\":false,\"error\":\"missing jeanne character or gaze cells\"}"); return 1 }
    for row in JeanneMotion.cycles.keys {
        for frame in 0..<16 {
            guard let image = JeanneFrames.image(row: row, frame: frame), image.size == NSSize(width: 448, height: 640) else { return 1 }
        }
    }
    for direction in 0..<16 {
        guard let image = JeanneFrames.image(row: direction < 8 ? 9 : 10, frame: direction % 8),
              image.size == NSSize(width: 448, height: 640) else { return 1 }
    }
    guard runJeanneClockSelfTest() == 0 else { return 1 }
    print("{\"ok\":true,\"characterCells\":160,\"gazeCells\":16}")
    return 0
}

/// 캐릭터 자세를 고정해도 별도의 경과 시간으로 효과를 그린다.
enum JeanneEffects {
    static func draw(state: PetState, drag: DragRun?, in rect: NSRect,
                     time: TimeInterval, frame: Int, front: Bool) {
        let id = JeanneMotion.id(state: state, drag: drag)
        let phase = ((time / 8).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let angle = phase * 2 * Double.pi
        let pulse = 0.65 + 0.25 * sin(angle)
        let scale = rect.width / 224
        func point(_ x: Double, _ y: Double) -> NSPoint {
            NSPoint(x: rect.minX + CGFloat(x) * scale, y: rect.maxY - CGFloat(y) * scale)
        }
        func stroke(_ path: NSBezierPath, _ color: UInt32, _ width: CGFloat, _ alpha: Double) {
            hexColor(color).withAlphaComponent(CGFloat(max(0, min(1, alpha)))).setStroke()
            path.lineWidth = width * scale
            path.lineCapStyle = .round
            path.stroke()
        }
        func star(_ x: Double, _ y: Double, _ radius: Double, _ alpha: Double) {
            let path = NSBezierPath()
            path.move(to: point(x, y - radius))
            path.line(to: point(x + radius * 0.22, y - radius * 0.22))
            path.line(to: point(x + radius, y))
            path.line(to: point(x + radius * 0.22, y + radius * 0.22))
            path.line(to: point(x, y + radius))
            path.line(to: point(x - radius * 0.22, y + radius * 0.22))
            path.line(to: point(x - radius, y))
            path.line(to: point(x - radius * 0.22, y - radius * 0.22))
            path.close()
            hexColor(0xFFE39B).withAlphaComponent(CGFloat(alpha)).setFill()
            path.fill()
            stroke(path, 0xD99B36, 0.35, alpha)
        }
        func seal(_ x: Double, _ y: Double, _ radius: Double, _ alpha: Double, broken: Bool = false) {
            let center = point(x, y)
            let path = NSBezierPath()
            if broken {
                path.appendArc(withCenter: center, radius: CGFloat(radius) * scale, startAngle: 0, endAngle: 70)
                path.move(to: point(x - radius, y))
                path.appendArc(withCenter: center, radius: CGFloat(radius) * scale, startAngle: 180, endAngle: 255)
            } else {
                path.appendOval(in: NSRect(x: center.x - CGFloat(radius) * scale,
                                          y: center.y - CGFloat(radius) * scale,
                                          width: CGFloat(radius * 2) * scale,
                                          height: CGFloat(radius * 2) * scale))
            }
            path.move(to: point(x, y - radius - 2)); path.line(to: point(x, y + radius + 2))
            path.move(to: point(x - radius - 2, y)); path.line(to: point(x + radius + 2, y))
            stroke(path, 0xEAC56D, 1, alpha)
        }
        if front {
            switch id {
            case "running":
                seal(104 + cos(angle) * 14, 175 + sin(angle) * 7, 7, pulse)
                star(98, 178, 3, pulse)
            case "review": seal(58, 145, 8, pulse)
            case "waiting":
                let q = (phase * 2).truncatingRemainder(dividingBy: 1)
                seal(104, 177, 4 + q * 9, 1 - q)
            case "failed":
                let q = (phase * 2).truncatingRemainder(dividingBy: 1)
                seal(52 - q * 5, 208 - q * 4, 6 + q * 3, (1 - q) * 0.6, broken: true)
            case "waving": seal(61, 150, 7, pulse); star(169, 118, 4, pulse)
            case "sleeping":
                let path = NSBezierPath()
                path.appendArc(withCenter: point(177, 196), radius: 7 * scale, startAngle: 70, endAngle: 290)
                stroke(path, 0xEFD893, 1.2, 0.55)
            case "idle": seal(72, 183, 4, pulse * 0.7)
            default: break
            }
            for i in 0..<3 {
                let q = (phase + Double(i) * 0.31).truncatingRemainder(dividingBy: 1)
                star(48 + Double(i) * 56 + sin(q * 2 * .pi) * 4,
                     (id == "sleeping" ? 248 : 242) - sin(q * 2 * .pi) * 5,
                     1.4 + sin(q * .pi), id == "sleeping" ? 0.25 : 0.25 + 0.4 * sin(q * .pi))
            }
            return
        }
        if id == "running" {
            let path = NSBezierPath()
            path.move(to: point(172, 112))
            path.curve(to: point(102, 178), controlPoint1: point(155, 131),
                       controlPoint2: point(145 + sin(angle) * 5, 150))
            stroke(path, 0xEDCE80, 0.7, pulse * 0.55)
        }
        if id == "jumping" {
            let landing = max(0, sin(Double(frame) / 16 * 2 * .pi - .pi / 2))
            let c = point(100, 281), rx = CGFloat(13 + landing * 12) * scale, ry = CGFloat(3 + landing * 2) * scale
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
            stroke(path, 0xE8C56E, 0.8, landing * 0.7)
        }
        if id != "sleeping" {
            let direction: Double = id == "drag-left" ? -1 : 1
            let offset = sin(angle) * 3
            let x1: Double = direction == 1 ? 45 : 179, x2: Double = direction == 1 ? 128 : 96, x3: Double = direction == 1 ? 174 : 50
            let path = NSBezierPath()
            path.move(to: point(x1, 255 + offset))
            path.curve(to: point(x3, 253 - offset), controlPoint1: point(x1 + direction * 24, 273 - offset),
                       controlPoint2: point(x2, 266 + offset))
            stroke(path, 0xC62943, 3.3, id == "idle" ? 0.4 : 0.65)
            stroke(path, 0xF0C679, 0.55, id == "idle" ? 0.3 : 0.48)
        }
        for i in 0..<2 {
            let q = (phase + Double(i) * 0.47).truncatingRemainder(dividingBy: 1)
            let x: Double = id.hasPrefix("drag") ? (id == "drag-left" ? 180 + q * 13 : 40 - q * 13) : 36 + Double(i) * 142 + sin(q * 2 * .pi) * 4
            let y = id == "sleeping" ? 233 + sin(q * 2 * .pi) * 7 : 269 - q * 36
            let path = NSBezierPath()
            path.move(to: point(x, y - 7))
            path.curve(to: point(x, y + 8), controlPoint1: point(x + 8, y - 5), controlPoint2: point(x + 6, y + 5))
            path.curve(to: point(x, y - 7), controlPoint1: point(x - 5, y + 4), controlPoint2: point(x - 6, y - 4))
            hexColor(0xFFF7EA).withAlphaComponent(CGFloat(0.25 + 0.35 * sin(q * .pi))).setFill()
            path.fill()
            stroke(path, 0xD7C5AA, 0.35, 0.45)
        }
    }
}

func runJeanneClockSelfTest() -> Int32 {
    let delayed = JeanneMotion.position(elapsed: 0.51, interval: 0.1)
    let next = JeanneMotion.position(elapsed: 1.69, interval: 0.1)
    guard delayed.frame == 5, delayed.cycles == 0, next.frame == 0, next.cycles == 1 else { return 1 }
    func pixels(state: PetState, drag: DragRun?, time: Double) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 224, pixelsHigh: 320,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 224, height: 320).fill()
        for front in [false, true] {
            JeanneEffects.draw(state: state, drag: drag, in: NSRect(x: 0, y: 0, width: 224, height: 320),
                               time: time, frame: 0, front: front)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return nil }
        return Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    let cases: [(PetState, DragRun?)] = PetState.allCases.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    for (state, drag) in cases {
        guard let a = pixels(state: state, drag: drag, time: 0.125),
              let b = pixels(state: state, drag: drag, time: 0.875),
              let c = pixels(state: state, drag: drag, time: 8.125), a != b, a == c else {
            print("jeanne: effect clock failed \(JeanneMotion.id(state: state, drag: drag))")
            return 1
        }
    }
    print("{\"ok\":true,\"frozenPoseChecks\":10,\"effectPeriod\":8,\"redrawHz\":60}")
    return 0
}

func renderJeanneMotionPreview(to path: String, gaze: Bool = false) -> Int32 {
    registerRettoFont()
    let entries: [(PetState, DragRun?)] = gaze ? [(.idle, nil)] : PetState.allCases.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    let size = NSSize(width: 16 * 224, height: entries.count * 2 * 320)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let scale: CGFloat = 224 / basePetWidth
    let layout = petLayout(scale: scale)
    for (index, entry) in entries.enumerated() {
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: JeanneFrames.placeholder,
                             skin: .jeanne, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        view.petScale = scale
        let json = "{\"state\":\"\(entry.0.rawValue)\",\"sessionId\":\"jeanne-review\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: json) else { return 1 }
        view.apply(payload, sessionCount: 1, attentionCount: 0, isPinned: false)
        view.setDragRunForPreview(entry.1)
        view.settleAnimations()
        for dark in 0..<2 {
            for frame in 0..<16 {
                let x = CGFloat(frame * 224), y = size.height - CGFloat((index * 2 + dark + 1) * 320)
                (dark == 0 ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)).setFill()
                NSRect(x: x, y: y, width: 224, height: 320).fill()
                view.setFrameForPreview(frame)
                if gaze { view.setGazeDirectionForPreview(frame) }
                view.setJeanneTimeForPreview(Double(frame) * (JeanneMotion.cycles[animationCatalog[entry.0]!.row] ?? 3.2) / 16)
                NSGraphicsContext.saveGraphicsState()
                NSRect(x: x, y: y, width: 224, height: 320).clip()
                let transform = NSAffineTransform()
                transform.translateX(by: x - layout.petRect.minX, yBy: y - layout.petRect.minY)
                transform.concat()
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return 1 }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    return 0
}
