import AppKit
import Foundation

func runMagicalHeartClockSelfTest() -> Int32 {
    let delayed = MagicalHeartMotion.position(elapsed: 4.37, frames: 8, interval: 0.25)
    let boundary = MagicalHeartMotion.position(elapsed: 2, frames: 8, interval: 0.25)
    let invalid = MagicalHeartMotion.position(elapsed: .nan, frames: 0, interval: 0)
    guard delayed.frame == 1, delayed.cycles == 2,
          boundary.frame == 0, boundary.cycles == 1,
          invalid.frame == 0, invalid.cycles == 0 else {
        print("FAIL: Magical Heart delayed callback / cycle boundary")
        return 1
    }
    for state in PetState.allCases {
        guard let animation = animationCatalog[state] else { continue }
        let end = MagicalHeartMotion.position(elapsed: Double(animation.frames) * animation.interval + 0.0001,
                                              frames: animation.frames, interval: animation.interval)
        guard end.frame == 0, end.cycles == 1 else { return 1 }
        let upgraded = skinAnimation(animation, skin: .magicalHeart, columns: 16)
        guard upgraded.frames == 16,
              abs(upgraded.interval * 16 - MagicalHeartMotion.cycleSeconds[animation.row]!) < 0.0001,
              skinAnimation(animation, skin: .magicalHeart, columns: 8).frames == animation.frames else { return 1 }
    }
    print("PASS: Magical Heart elapsed time, delayed callbacks and cycle boundaries")
    return 0
}

/// 실제 RettoView를 224×320으로 그려 고정 포즈에서도 효과가 진행하는지 확인한다.
func renderMagicalHeartMotionPreview(to directory: String) -> Int32 {
    registerRettoFont()
    guard let url = Bundle.main.url(forResource: PetSkin.magicalHeart.resourceName, withExtension: "webp"),
          let atlas = NSImage(contentsOf: url) else { return 1 }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    catch { return 1 }
    let entries: [(PetState, DragRun?, Int?)] = [
        (.idle, nil, nil), (.running, nil, nil), (.review, nil, nil), (.waiting, nil, nil),
        (.failed, nil, nil), (.waving, nil, nil), (.jumping, nil, nil), (.sleeping, nil, nil),
        (.idle, .right, nil), (.idle, .left, nil), (.idle, nil, 0), (.running, nil, 12)
    ]
    var views: [RettoView] = []
    let columns = SpriteSheetLayout.forImage(size: atlas.size)?.columns ?? 8
    for (state, drag, gaze) in entries {
        let view = RettoView(frame: NSRect(origin: .zero, size: petLayout(scale: 224 / 294).windowSize),
                             spriteSheet: atlas, skin: .magicalHeart,
                             onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        view.petScale = 224 / 294
        view.setMagicalHeartSpriteOnlyForPreview()
        let fixture = "{\"state\":\"idle\",\"sessionId\":\"preview\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { return 1 }
        view.apply(payload, state: state, sessionCount: 1, attentionCount: 0, isPinned: false)
        view.settleAnimations()
        view.setDragRunForPreview(drag)
        if let gaze { view.setGazeDirectionForPreview(gaze) }
        views.append(view)
    }
    for dark in [false, true] {
        for tick in 0..<40 {
            let time = Double(tick) * 0.1
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 896, pixelsHigh: 960,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            (dark ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor.white).setFill()
            NSRect(x: 0, y: 0, width: 896, height: 960).fill()
            for (index, entry) in entries.enumerated() {
                let view = views[index]
                let original = entry.1.flatMap { dragRunAnimations[$0] } ?? animationCatalog[entry.0]!
                let animation = skinAnimation(original, skin: .magicalHeart, columns: columns)
                let position = MagicalHeartMotion.position(elapsed: time, frames: animation.frames, interval: animation.interval)
                view.setFrameForPreview(position.frame)
                view.setMagicalHeartTimeForPreview(time)
                let layout = petLayout(scale: view.petScale)
                let cell = NSRect(x: CGFloat(index % 4) * 224, y: CGFloat(2 - index / 4) * 320, width: 224, height: 320)
                NSGraphicsContext.saveGraphicsState()
                cell.clip()
                let transform = NSAffineTransform()
                transform.translateX(by: cell.minX - layout.petRect.minX, yBy: cell.minY - layout.petRect.minY)
                transform.concat()
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return 1 }
            let name = String(format: "%@-%03d.png", dark ? "dark" : "white", tick)
            do { try data.write(to: output.appendingPathComponent(name)) } catch { return 1 }
        }
    }
    print("PASS: 80 native boards, 1× cells, 4 seconds per background, gaze holds included")
    return 0
}
