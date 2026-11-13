// Windows 판 스킨 프레임 내보내기 — `Retto --export-windows-skins <폴더> [--fps 15] [--scale 0.8]`.
//
// Windows 판은 스킨을 다시 짜지 않고, 맥 앱이 실제로 그리는 그림을 프레임으로 받아 재생한다. 스킨마다 다른
// 효과·위치 보정·잠 호흡·쉬는 자세 전환까지 맥과 같게 나온다. RettoView 를 가짜 시계(exportClock)로 돌려
// 타이머가 울렸을 차례마다 실제와 같은 advanceFrame 을 부르고, 그 시각의 그림을 저장한다.
//
// 남기는 것 — 스킨마다 `<스킨>/<클립>.png`(프레임을 cols 칸씩 줄지어 붙인 판)와 `manifest.json`.
// 클립: 8개 상태, 끌 때 좌우 달리기, 시선 16방향(시선을 쓰는 스킨만). 마우스·클릭 반응 같은 입력 쪽 동작은
// Windows 판이 이 클립을 골라 재생하는 것으로 옮긴다. 무작위로 고르는 변형은 한 번 뽑힌 것만 담긴다.

import AppKit

private let exportStates: [PetState] = [.idle, .running, .review, .waiting, .failed, .waving, .jumping, .sleeping]
private let exportColumns = 10

private func exportPayload(_ state: PetState) -> StatePayload? {
    try? JSONDecoder().decode(StatePayload.self,
        from: Data("{\"state\":\"\(state.rawValue)\",\"sessionId\":\"windows-export\",\"projectName\":\"Retto\"}".utf8))
}

private func exportSheet(_ skin: PetSkin) -> NSImage? {
    if skin == .amuRan { return NSImage(size: NSSize(width: 7168, height: 7680)) }
    if skin == .hachupingping { return HachupingSkin.placeholder }
    if skin == .howl { return HowlSkin.placeholder }
    if skin == .jeanne { return JeanneSkin.placeholder }
    if skin == .pichiPitch { return PichiSkin.placeholder }
    if skin == .chocolatHeart { return ChocolatHeart.placeholder }
    if skin == .hana { return HanaFrameCache.placeholder }
    guard let url = Bundle.main.url(forResource: skin.resourceName, withExtension: "webp") else { return nil }
    return NSImage(contentsOf: url)
}

private struct ExportCanvas {
    let window: NSSize
    let crop: NSRect

    /// 창 전체를 그린 뒤 캐릭터 둘레만 잘라 낸다. 효과가 몸 밖으로 나가도 잘리지 않게 둘레를 둔다.
    func render(_ view: RettoView) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(window.width.rounded(.up)),
                pixelsHigh: Int(window.height.rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = window
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: window).fill()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        // CGImage 자르기는 왼쪽 위가 원점이다.
        let flipped = CGRect(x: crop.minX, y: window.height - crop.maxY, width: crop.width, height: crop.height)
        return rep.cgImage?.cropping(to: flipped.integral)
    }
}

/// 프레임들을 cols 칸씩 줄지어 붙인 PNG 한 장으로 쓴다.
private func writeSheet(_ frames: [CGImage], to url: URL, width: Int, height: Int) -> Bool {
    let columns = min(exportColumns, max(1, frames.count))
    let rows = (frames.count + columns - 1) / columns
    guard let context = CGContext(data: nil, width: width * columns, height: height * rows, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    for (index, frame) in frames.enumerated() {
        let column = index % columns, row = index / columns
        context.draw(frame, in: CGRect(x: column * width, y: (rows - 1 - row) * height, width: width, height: height))
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func exportWindowsSkins(to path: String) -> Int32 {
    registerRettoFont()
    let arguments = CommandLine.arguments
    func value(_ flag: String) -> Double? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return Double(arguments[i + 1])
    }
    let fps = value("--fps") ?? 15
    let scale = CGFloat(value("--scale") ?? 0.8)
    let only = arguments.firstIndex(of: "--skins").flatMap { i in i + 1 < arguments.count ? Set(arguments[i + 1].split(separator: ",").map(String.init)) : nil }
    let root = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let layout = petLayout(scale: scale)
    let margin = 40 * scale
    let crop = layout.petRect.insetBy(dx: -margin, dy: -margin * 0.75)
        .intersection(NSRect(origin: .zero, size: layout.windowSize)).integral
    let canvas = ExportCanvas(window: layout.windowSize, crop: crop)
    let frameWidth = Int(crop.width), frameHeight = Int(crop.height)
    var skins: [[String: Any]] = []

    for skin in PetSkin.selectableCases where skin.isAvailable && (only == nil || only!.contains(skin.rawValue)) {
        guard let sheet = exportSheet(skin) else { continue }
        let folder = root.appendingPathComponent(skin.rawValue)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var clips: [String: Any] = [:]
        let started = Date()

        func freshView() -> RettoView {
            let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: sheet, skin: skin,
                                 onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
            view.exportClock = 1000
            view.exportResetEpochs()
            view.exportSpriteOnly = true
            view.petScale = scale
            return view
        }

        /// 한 클립을 녹화한다. 쉬는 자세로 넘어가면(완료 손 흔들기 등) 거기서 멈추고 다음 클립을 적는다.
        func record(_ name: String, state: PetState, drag: DragRun? = nil) {
            let view = freshView()
            guard let payload = exportPayload(state == .sleeping ? .idle : state) else { return }
            view.apply(payload, state: state == .sleeping ? .idle : state, sleepPose: state == .sleeping,
                       sessionCount: 1, attentionCount: 0, isPinned: false)
            view.settleAnimations()
            if let drag { view.setDragRunForPreview(drag) }
            view.exportRestart()
            let limit = view.exportCycleLimit
            // 반복 클립은 동작 한 바퀴의 정수배로 녹화한다. 이어 돌릴 때 중간 자세에서 처음 자세로 튀지 않게.
            // (몸과 효과의 주기가 다른 스킨은 몸 주기에 맞춘다.) 2초보다 짧으면 여러 바퀴, 12초까지.
            let cycle = max(0.05, view.exportCycleSeconds)
            let duration = limit != nil ? 8.0 : min(max(12.0, cycle), cycle * max(1, (2.0 / cycle).rounded(.up)))
            let count = max(1, Int((duration * fps).rounded()))
            let cycleFrames = max(1, Int((view.exportCycleSeconds * fps).rounded()))
            let startVisible = view.exportVisibleState
            var frames: [CGImage] = []
            var then: String?
            for i in 0..<count {
                view.exportAdvance(to: 1000 + Double(i) / fps)
                if drag == nil, view.exportVisibleState != startVisible { then = view.exportVisibleState.rawValue; break }
                guard let image = canvas.render(view) else { continue }
                frames.append(image)
            }
            guard !frames.isEmpty, writeSheet(frames, to: folder.appendingPathComponent("\(name).png"), width: frameWidth, height: frameHeight) else { return }
            var clip: [String: Any] = ["file": "\(name).png", "frames": frames.count, "fps": fps,
                                       "columns": min(exportColumns, frames.count), "loop": then == nil,
                                       "cycleFrames": min(cycleFrames, frames.count)]
            if let then { clip["then"] = then }
            clips[name] = clip
        }

        for state in exportStates { record(state.rawValue, state: state) }
        record("drag-left", state: .idle, drag: .left)
        record("drag-right", state: .idle, drag: .right)

        // 시선 16방향. 시선을 쓰는 스킨만 쉬는 중 자세로 한 장씩 담는다.
        let gazeView = freshView()
        if let payload = exportPayload(.idle) {
            gazeView.apply(payload, state: .idle, sessionCount: 1, attentionCount: 0, isPinned: false)
            gazeView.settleAnimations()
            gazeView.exportRestart()
            var gazeFrames: [CGImage] = []
            for direction in 0..<16 {
                gazeView.setGazeDirectionForPreview(direction)
                gazeView.exportAdvance(to: 1000 + Double(direction) * 0.25)
                guard gazeView.exportHasActiveGaze, let image = canvas.render(gazeView) else { gazeFrames = []; break }
                gazeFrames.append(image)
            }
            if gazeFrames.count == 16, writeSheet(gazeFrames, to: folder.appendingPathComponent("gaze.png"), width: frameWidth, height: frameHeight) {
                clips["gaze"] = ["file": "gaze.png", "frames": 16, "fps": 0, "columns": min(exportColumns, 16), "loop": false]
            }
        }
        skins.append(["id": skin.rawValue, "label": skin.label, "clips": clips])
        print("\(skin.rawValue): \(clips.count) clips · \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    }

    let manifest: [String: Any] = [
        "version": 1,
        "frameWidth": frameWidth,
        "frameHeight": frameHeight,
        "scale": scale,
        // 캐릭터 칸(petRect)이 프레임 안 어디인지. 왼쪽 위 원점, 픽셀.
        "petRect": ["x": layout.petRect.minX - crop.minX, "y": crop.maxY - layout.petRect.maxY,
                    "width": layout.petRect.width, "height": layout.petRect.height],
        "skins": skins
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return 1 }
    do { try data.write(to: root.appendingPathComponent("manifest.json")) } catch { return 1 }
    return skins.isEmpty ? 1 : 0
}
