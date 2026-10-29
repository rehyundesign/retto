import AppKit
import Foundation

/// 목·어깨·가슴이 연결된 16방향 전신 시선 컷을 사용한다.
enum HanaGaze {
    static func allows(state: PetState, dragging: Bool) -> Bool {
        gazeStates.contains(state) && !dragging
    }
    static func cell(direction: Int) -> (row: Int, column: Int) {
        let direction = (direction % gazeDirectionCount + gazeDirectionCount) % gazeDirectionCount
        return (9 + direction / 8, direction % 8)
    }
    @discardableResult
    static func draw(direction: Int, in rect: NSRect) -> Bool {
        let (row, column) = cell(direction: direction)
        return HanaFrameCache.drawCharacter(row: row, frame: column, in: rect)
    }
    static func selfTest() -> Bool {
        guard PetState.allCases.allSatisfy({ allows(state: $0, dragging: false) == gazeStates.contains($0) }),
              !allows(state: .idle, dragging: true) else { return false }
        var sources = Set<Data>()
        for direction in 0..<gazeDirectionCount {
            let (row, column) = cell(direction: direction)
            guard row == 9 + direction / 8, column == direction % 8,
                  let image = HanaFrameCache.image("character-\(row)-\(column)", character: true),
                  image.size == NSSize(width: 448, height: 640),
                  let data = image.tiffRepresentation else {
                print("hana gaze: missing or invalid head pose \(direction)"); return false
            }
            sources.insert(data)
        }
        guard sources.count == gazeDirectionCount,
              nextGazeDirection(from: 15, toward: 0) == 0,
              nextGazeDirection(from: 0, toward: 15) == 15 else { return false }
        let layout = petLayout(scale: 1)
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize),
                             spriteSheet: HanaFrameCache.placeholder, skin: .hana,
                             onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        guard view.verifyHanaGazeBehaviorForTesting() else { print("hana gaze: behavior failed"); return false }
        print("hana gaze: 16 complete-source gaze poses, reset timer, state/drag/sleep/reaction gates and wrap transition passed")
        return true
    }
    static func renderPreview(to directory: String) -> Int32 {
        let root = URL(fileURLWithPath: directory)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return 1 }
        let scale: CGFloat = 224 / basePetWidth
        let layout = petLayout(scale: scale)
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize),
                             spriteSheet: HanaFrameCache.placeholder, skin: .hana,
                             onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        view.petScale = scale
        view.settleAnimations()
        for direction in 0..<16 {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 448, pixelsHigh: 320,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            view.setGazeDirectionForPreview(direction)
            view.setChristmasTimeForPreview(Double(direction) * 0.12)
            for dark in 0..<2 {
                let x = CGFloat(dark * 224)
                (dark == 0 ? NSColor.white : NSColor(calibratedWhite: 0.14, alpha: 1)).setFill()
                NSRect(x: x, y: 0, width: 224, height: 320).fill()
                NSGraphicsContext.saveGraphicsState()
                NSRect(x: x, y: 0, width: 224, height: 320).clip()
                let transform = NSAffineTransform()
                transform.translateX(by: x - layout.petRect.minX, yBy: -layout.petRect.minY)
                transform.concat()
                let rect = layout.petRect
                let time = Double(direction) * 0.12
                let effects = HanaEffectLayers()
                effects.draw(state: .idle, drag: nil, in: rect, time: time, front: false)
                guard draw(direction: direction, in: rect) else { return 1 }
                effects.draw(state: .idle, drag: nil, in: rect, time: time, front: true)
                NSGraphicsContext.restoreGraphicsState()
                let angle = CGFloat(direction) * .pi / 8
                let cursor = NSPoint(x: x + 98 + sin(angle) * 79, y: 190 + cos(angle) * 70)
                NSColor.systemPink.setFill()
                NSBezierPath(ovalIn: NSRect(x: cursor.x - 3, y: cursor.y - 3, width: 6, height: 6)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return 1 }
            do { try png.write(to: root.appendingPathComponent(String(format: "%02d.png", direction))) } catch { return 1 }
        }
        return 0
    }
}
