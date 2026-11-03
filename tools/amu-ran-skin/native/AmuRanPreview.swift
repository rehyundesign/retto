import AppKit
import Foundation

func runAmuRanClockSelfTest() -> Int32 {
    let delayed = AmuRanMotion.position(elapsed: 4.37, frames: 8, interval: 0.25)
    let boundary = AmuRanMotion.position(elapsed: 2, frames: 8, interval: 0.25)
    let invalid = AmuRanMotion.position(elapsed: .nan, frames: 0, interval: 0)
    guard delayed.frame == 1, delayed.cycles == 2,
          boundary.frame == 0, boundary.cycles == 1,
          invalid.frame == 0, invalid.cycles == 0 else {
        print("FAIL: Amu & Ran delayed callback / cycle boundary")
        return 1
    }
    for state in PetState.allCases {
        guard let animation = animationCatalog[state] else { continue }
        let end = AmuRanMotion.position(elapsed: Double(animation.frames) * animation.interval + 0.0001,
                                              frames: animation.frames, interval: animation.interval)
        guard end.frame == 0, end.cycles == 1 else { return 1 }
        let upgraded = skinAnimation(animation, skin: .amuRan, columns: 16)
        guard upgraded.frames == 16,
              abs(upgraded.interval * 16 - AmuRanMotion.cycleSeconds[animation.row]!) < 0.0001,
              skinAnimation(animation, skin: .amuRan, columns: 8).frames == animation.frames else { return 1 }
    }
    for (row,cycle) in AmuRanMotion.cycles {
        for frame in 0...16 {
            let position = AmuRanMotion.position(elapsed:Double(frame)*cycle/16, interval:cycle/16)
            guard position.frame == frame % 16, position.cycles == frame / 16 else {
                print("FAIL: exact Amu & Ran boundary row \(row), frame \(frame)"); return 1
            }
        }
    }
    guard AmuRanMotion.gazeRow(state:.waving) == 10,
          AmuRanMotion.gazeRow(state:.idle) == 9,
          AmuRanMotion.gazeRow(state:.running) == 9 else { return 1 }
    // A newly started completion must not inherit the global effect phase.
    guard let contact = AmuRanInteraction.sample(row:3, poseTime:1.05, effectTime:123.7),
          let start = AmuRanInteraction.sample(row:3, poseTime:0, effectTime:1.05),
          contact.side == "left", contact.pose == 3, start.pose == 0,
          abs(contact.point.x - 12) <= 1, abs(contact.point.y - 389) <= 1,
          let gazeA = AmuRanInteraction.sample(row:3, poseTime:0, effectTime:0.1, gazeDirection:4),
          let gazeB = AmuRanInteraction.sample(row:3, poseTime:0, effectTime:1.1, gazeDirection:4),
          gazeA.pose != gazeB.pose, gazeA.side == "right", gazeB.side == "right" else {
        print("FAIL: partner response did not follow the state clock / held gaze"); return 1
    }
    print("PASS: Amu & Ran elapsed time, boundaries, state-relative partner response and held-gaze breathing")
    return 0
}

/// 실제 RettoView를 224×320으로 그려 고정 포즈에서도 효과가 진행하는지 확인한다.
func renderAmuRanMotionPreview(to directory: String) -> Int32 {
    registerRettoFont()
    guard let url = Bundle.main.url(forResource: PetSkin.amuRan.resourceName, withExtension: "webp"),
          let atlas = NSImage(contentsOf: url) else { return 1 }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    catch { return 1 }
    let entries: [(PetState, DragRun?, Int?)] = [
        (.idle, nil, nil), (.running, nil, nil), (.review, nil, nil), (.waiting, nil, nil),
        (.failed, nil, nil), (.waving, nil, nil), (.jumping, nil, nil), (.sleeping, nil, nil),
        (.idle, .right, nil), (.idle, .left, nil), (.idle, nil, 0), (.waving, nil, 12)
    ]
    var views: [RettoView] = []
    let columns = SpriteSheetLayout.forImage(size: atlas.size)?.columns ?? 8
    for (state, drag, gaze) in entries {
        let view = RettoView(frame: NSRect(origin: .zero, size: petLayout(scale: 224 / 294).windowSize),
                             spriteSheet: atlas, skin: .amuRan,
                             onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        view.petScale = 224 / 294
        view.setAmuRanSpriteOnlyForPreview()
        let fixture = "{\"state\":\"idle\",\"sessionId\":\"preview\",\"projectName\":\"Retto\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { return 1 }
        view.apply(payload, state: state, sessionCount: 1, attentionCount: 0, isPinned: false)
        view.settleAnimations()
        view.setDragRunForPreview(drag)
        if let gaze { view.setGazeDirectionForPreview(gaze) }
        views.append(view)
    }
    for dark in [false, true] {
        for tick in 0..<80 {
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
                let animation = skinAnimation(original, skin: .amuRan, columns: columns)
                let position = AmuRanMotion.position(elapsed: time, frames: animation.frames, interval: animation.interval)
                view.setFrameForPreview(position.frame)
                view.setAmuRanTimeForPreview(time)
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
    print("PASS: 160 native boards, 1× cells, 8 seconds per background, gaze holds included")
    return 0
}

func renderAmuRanGazePreview(to directory: String) -> Int32 {
    guard AmuRanFrames.hasAllFrames else { print("FAIL: incomplete Amu & Ran resources"); return 1 }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) } catch { return 1 }
    let atlas = NSImage(size: NSSize(width: 7168, height: 7680))
    let data = "{\"state\":\"idle\",\"sessionId\":\"preview\",\"projectName\":\"Retto\"}".data(using: .utf8)!
    guard let payload = try? JSONDecoder().decode(StatePayload.self, from: data) else { return 1 }
    for (state, costume) in [(PetState.idle,"school"), (PetState.waving,"heart")] {
        for dark in [false,true] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 896, pixelsHigh: 1280,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 1 }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            (dark ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor.white).setFill()
            NSRect(x:0,y:0,width:896,height:1280).fill()
            for direction in 0..<16 {
                let view = RettoView(frame: NSRect(origin: .zero, size: petLayout(scale:224/294).windowSize),
                                     spriteSheet: atlas, skin: .amuRan, onOpenClaude: { _,_ in }, onOpenAttention: { _ in })
                view.petScale = 224/294; view.setAmuRanSpriteOnlyForPreview()
                view.apply(payload, state: state, sessionCount:1, attentionCount:0, isPinned:false)
                view.settleAnimations(); view.setGazeDirectionForPreview(direction); view.setAmuRanTimeForPreview(0.7)
                let layout = petLayout(scale:view.petScale)
                let cell = NSRect(x:CGFloat(direction%4)*224,y:CGFloat(3-direction/4)*320,width:224,height:320)
                NSGraphicsContext.saveGraphicsState();cell.clip()
                let transform = NSAffineTransform();transform.translateX(by:cell.minX-layout.petRect.minX,yBy:cell.minY-layout.petRect.minY);transform.concat()
                view.draw(view.bounds);NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using:.png,properties:[:]) else { return 1 }
            do { try png.write(to:output.appendingPathComponent("gaze-\(costume)-\(dark ? "dark" : "light").png")) } catch { return 1 }
        }
    }
    print("PASS:32 gaze directions through RettoView, both costumes and backgrounds")
    return 0
}
