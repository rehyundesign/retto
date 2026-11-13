// Local performance validation uses generated temporary fixtures only.
// 실행 진입점. 진단 플래그를 먼저 처리한다.

import AppKit
if let i = CommandLine.arguments.firstIndex(of: "--render-classic-gaze-preview"), i + 1 < CommandLine.arguments.count { exit(renderClassicGazePreview(to: CommandLine.arguments[i+1])) }
if CommandLine.arguments.contains("--transcript-stream-self-test") { exit(runTranscriptStreamSelfTest()) }
if let i = CommandLine.arguments.firstIndex(of: "--benchmark-transcript-scan"), i + 1 < CommandLine.arguments.count {
    exit(benchmarkTranscriptScan(path: CommandLine.arguments[i+1], wholeFile: CommandLine.arguments.contains("--whole-file")))
}
if CommandLine.arguments.contains("--frame-cache-self-test") { exit(runFrameCacheSelfTest()) }
if CommandLine.arguments.contains("--benchmark-angel-frames") { exit(benchmarkAngelFrames()) }
if CommandLine.arguments.contains("--classic-gaze-self-test") { let ok = ClassicGrown.gazeSelfTest(); print("Classic16 directional gaze: \(ok)"); exit(ok ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--render-classic-grown-preview"), i + 1 < CommandLine.arguments.count { exit(renderClassicGrownPreview(to: CommandLine.arguments[i+1])) }
if CommandLine.arguments.contains("--classic-grown-self-test") { let ok = ClassicGrown.selfTest(); print("Classic grown: \(ok)"); exit(ok ? 0 : 1) }
import CoreText
import Foundation
if CommandLine.arguments.contains("--angel-interactions-state-test") {
 let v=RettoView(frame:NSRect(x:0,y:0,width:400,height:500),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
 exit(v.validateAngelInteractions() ? 0:1)
}
if let i=CommandLine.arguments.firstIndex(of:"--render-angel-interactions"),i+1<CommandLine.arguments.count {exit(renderAngelInteractions(to:CommandLine.arguments[i+1]))}
if CommandLine.arguments.contains("--angel-interactions-self-test"){exit(AngelInteractions.validate() ? 0:1)}
if CommandLine.arguments.contains("--angel-state-self-test") {
 let v=RettoView(frame:NSRect(x:0,y:0,width:400,height:500),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
 exit(v.validateAngelTransitions() ? 0:1)
}

if CommandLine.arguments.contains("--angel-self-test"){exit(AngelSkin.validate() ? 0:1)}
if let i=CommandLine.arguments.firstIndex(of:"--render-angel-preview"),i+1<CommandLine.arguments.count {
 let time=i+2<CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.9:0.9
 exit(renderAngelPreview(to:CommandLine.arguments[i+1],time:time))
}

if CommandLine.arguments.contains("--amu-random-state-test") {
    let v=RettoView(frame:NSRect(x:0,y:0,width:306,height:460),spriteSheet:NSImage(size:NSSize(width:7168,height:7680)),skin:.amuRan,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
    exit(v.validateAmuRandomStates() ? 0:1)
}

if CommandLine.arguments.contains("--amu-approved-state-test") {
    let v=RettoView(frame:NSRect(x:0,y:0,width:306,height:460),spriteSheet:NSImage(size:NSSize(width:7168,height:7680)),skin:.amuRan,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
    exit(v.validateAmuApprovedTransitions() ? 0:1)
}

if CommandLine.arguments.contains("--amu-approved-self-test") { exit(AmuApproved.validate() ? 0:1) }

if let i=CommandLine.arguments.firstIndex(of:"--render-hachuping-drag-fit"),i+1<CommandLine.arguments.count {
 let t=i+2<CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.4:0.4
 exit(renderHachupingDragFit(to:CommandLine.arguments[i+1],time:t))
}
if let i=CommandLine.arguments.firstIndex(of:"--render-hachuping-current"),i+1<CommandLine.arguments.count {
 let t=i+2<CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.8:0.8
 exit(renderHachupingCurrent(to:CommandLine.arguments[i+1],time:t,held:CommandLine.arguments.contains("--hold-hachuping-pose"),dark:CommandLine.arguments.contains("--dark")))
}
if CommandLine.arguments.contains("--hachuping-self-test") {exit(HachupingSkin.validate() ? 0:1)}
if CommandLine.arguments.contains("--hachuping-state-self-test") {
 let v=RettoView(frame:NSRect(x:0,y:0,width:306,height:460),spriteSheet:HachupingSkin.placeholder,skin:.hachupingping,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
 exit(v.validateHachupingTransitions() ? 0:1)
}
if let i=CommandLine.arguments.firstIndex(of:"--render-hachuping-preview"),i+1<CommandLine.arguments.count {
 let t=i+2<CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.8:0.8
 exit(renderHachupingPreview(to:CommandLine.arguments[i+1],time:t,held:CommandLine.arguments.contains("--hold-hachuping-pose")))
}
if CommandLine.arguments.contains("--howl-self-test") { exit(HowlSkin.validate() ? 0 : 1) }
if CommandLine.arguments.contains("--howl-state-self-test") {
    let v = RettoView(frame:NSRect(x:0,y:0,width:306,height:460),spriteSheet:HowlSkin.placeholder,skin:.howl,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
    exit(v.validateHowlTransitions() ? 0 : 1)
}
if let i = CommandLine.arguments.firstIndex(of:"--render-howl-preview"), i+1 < CommandLine.arguments.count {
    let t = i+2 < CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.8 : 0.8
    let pose = CommandLine.arguments.contains("--howl-pose-index") ? Int(t) : nil
    exit(renderHowlPreview(to:CommandLine.arguments[i+1],sample:t,pose:pose,held:CommandLine.arguments.contains("--hold-howl-pose")))
}
if CommandLine.arguments.contains("--self-test-all-skins") { exit(runAllSkinsSelfTest()) }
if let i = CommandLine.arguments.firstIndex(of: "--export-windows-skins"), i + 1 < CommandLine.arguments.count { exit(exportWindowsSkins(to: CommandLine.arguments[i + 1])) }
if CommandLine.arguments.contains("--self-test-amu-ran-clock") { exit(runAmuRanClockSelfTest()) }
if let i = CommandLine.arguments.firstIndex(of: "--render-amu-ran-motion-preview"), i + 1 < CommandLine.arguments.count { exit(renderAmuRanMotionPreview(to: CommandLine.arguments[i+1])) }
if let i = CommandLine.arguments.firstIndex(of: "--render-amu-ran-gaze-preview"), i + 1 < CommandLine.arguments.count { exit(renderAmuRanGazePreview(to: CommandLine.arguments[i+1])) }

// 접근성 권한이 이 앱에 실제로 붙어 있는지. 애드혹 서명이라 다시 빌드할 때마다 풀리고,
// 손쉬운 사용 목록에는 켜져 보이는데 실제로는 없는 상태가 된다. 그때 이걸로 확인한다.
if CommandLine.arguments.contains("--ax-check") {
    print(ClaudeAppNavigator.isPermitted ? "접근성 권한: 있음" : "접근성 권한: 없음")
    exit(ClaudeAppNavigator.isPermitted ? 0 : 1)
}

if CommandLine.arguments.contains("--jeanne-state-self-test") {
    let v = RettoView(frame:NSRect(x:0,y:0,width:224,height:320),spriteSheet:JeanneSkin.placeholder,skin:.jeanne,onOpenClaude:{ _,_ in },onOpenAttention:{ _ in })
    let ok = v.validateJeanneStateTransitions()
    print("Jeanne state/loop/drag/gaze transitions: \(ok)")
    exit(ok ? 0 : 1)
}



if CommandLine.arguments.contains("--jeanne-fit-self-test") {
    let v = RettoView(frame:NSRect(x:0,y:0,width:224,height:320),spriteSheet:JeanneSkin.placeholder,skin:.jeanne,onOpenClaude:{ _,_ in },onOpenAttention:{ _ in })
    let ok = v.validateJeanneBodyFitCache()
    print("Jeanne text cache invalidation: \(ok)")
    exit(ok ? 0 : 1)
}

if CommandLine.arguments.contains("--jeanne-effects-self-test") { exit(JeanneSkin.validateEffects() ? 0 : 1) }
if CommandLine.arguments.contains("--jeanne-self-test") { exit(JeanneSkin.validate() ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--render-jeanne-preview"), i + 1 < CommandLine.arguments.count { exit(renderJeannePreview(to: CommandLine.arguments[i + 1])) }

if CommandLine.arguments.contains("--pichi-self-test") { let ok = PichiSkin.validate(); print("{\"pichiOK\":\(ok)}"); exit(ok ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--render-pichi-preview"), i + 1 < CommandLine.arguments.count { exit(renderPichiPreview(to: CommandLine.arguments[i + 1])) }

if CommandLine.arguments.contains("--hana-ground-self-test"){exit(HanaGrounding.validate() ? 0:1)}
if let i=CommandLine.arguments.firstIndex(of:"--render-hana-grounding"),i+1<CommandLine.arguments.count {exit(renderHanaGrounding(to:CommandLine.arguments[i+1]))}
if CommandLine.arguments.contains("--hana-gaze-self-test") { exit(HanaGaze.selfTest() ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--render-hana-gaze-preview"), i + 1 < CommandLine.arguments.count { exit(HanaGaze.renderPreview(to: CommandLine.arguments[i+1])) }
if CommandLine.arguments.contains("--hana-self-test") {
    let ok = hanaSkinSelfTest(); print("{\"hanaOK\":\(ok)}"); exit(ok ? 0 : 1)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-hana-motion-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderHanaMotionPreview(to: CommandLine.arguments[index + 1]))
}

if let index=CommandLine.arguments.firstIndex(of:"--render-chocolat-preview"),index+1<CommandLine.arguments.count { exit(renderChocolatHeartPreview(to:CommandLine.arguments[index+1])) }
if CommandLine.arguments.contains("--chocolat-self-test") {
    let ok=ChocolatHeart.validate();print("chocolatOK: \(ok)");exit(ok ? 0:1)
}
if let index = CommandLine.arguments.firstIndex(of: "--attention-preview"), index + 1 < CommandLine.arguments.count {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)
    app.finishLaunching()
    exit(renderAttentionPreview(to: CommandLine.arguments[index + 1]))
}

if CommandLine.arguments.contains("--self-test-codex-input") {
    exit(runCodexInputSelfTest())
}

if CommandLine.arguments.contains("--self-test-status-rendering") {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: .aqua)
    app.finishLaunching()
    var output: URL?
    if let flag = CommandLine.arguments.firstIndex(of: "--status-render-output"), flag + 1 < CommandLine.arguments.count {
        output = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    }
    exit(runStatusRenderingSelfTest(outputDirectory: output))
}

if CommandLine.arguments.contains("--self-test-slack") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)
    app.finishLaunching()
    exit(runSlackSelfTest())
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

if CommandLine.arguments.contains("--codex-rollouts-json") {
    print(codexRolloutReport())
    exit(0)
}

/// 발바닥 메뉴의 「레토 제거」와 같은 코드를 화면 없이 돌린다.
/// 설치기가 스크립트로 깔아 주므로 지우는 쪽도 스크립트로 되는 편이 맞고,
/// 알림창을 클릭해야만 도는 코드는 시험해 볼 방법이 없다.
/// `--keep-app` 을 붙이면 앱 본체는 휴지통에 넣지 않는다.
if CommandLine.arguments.contains("--uninstall") {
    let outcome = performUninstall()
    for line in outcome.lines { print(line) }
    if let bundleID = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        print("· 앱 설정을 지웠습니다")
    }
    if !CommandLine.arguments.contains("--keep-app") {
        let bundleURL = Bundle.main.bundleURL
        let done = DispatchSemaphore(value: 0)
        var trashError: Error?
        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            trashError = error
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        if trashError == nil { print("· 앱을 휴지통으로 옮겼습니다") }
        else { print("· ⚠ 앱을 휴지통으로 옮기지 못했습니다 — \(bundleURL.path) 를 직접 지워 주세요") }
    }
    exit(outcome.hadProblem ? 1 : 0)
}

if CommandLine.arguments.contains("--shape-report") {
    // 이미지 없이 윤곽을 확인한다: 높이별 폭과 인접 선분 사이의 최대 꺾임 각도.
    func report(_ name: String, _ path: NSBezierPath) {
        let flat = path.flattened
        var pts: [NSPoint] = []
        var e = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<flat.elementCount {
            if case .closePath = flat.element(at: i, associatedPoints: &e) { continue }
            pts.append(e[0])
        }
        let bounds = path.bounds
        var maxTurn: CGFloat = 0
        for i in pts.indices {
            let a = pts[(i - 1 + pts.count) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
            let v1 = NSPoint(x: b.x - a.x, y: b.y - a.y), v2 = NSPoint(x: c.x - b.x, y: c.y - b.y)
            let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
            guard l1 > 0.4, l2 > 0.4 else { continue }
            let cosine = max(-1, min(1, (v1.x * v2.x + v1.y * v2.y) / (l1 * l2)))
            maxTurn = max(maxTurn, acos(cosine) * 180 / .pi)
        }
        print(String(format: "%@  %.2f × %.2f (비 %.4f)  최대 꺾임 %.1f°", name, bounds.width, bounds.height, bounds.width / bounds.height, maxTurn))
        for frac in [0.05, 0.2, 0.35, 0.5, 0.62, 0.75, 0.9] as [CGFloat] {
            let y = bounds.maxY - bounds.height * frac
            let band = pts.filter { abs($0.y - y) < bounds.height * 0.03 }.map(\.x)
            if let lo = band.min(), let hi = band.max() {
                print(String(format: "    위에서 %3.0f%% → 폭 %6.1f (%.1f%%)", frac * 100, hi - lo, (hi - lo) / bounds.width * 100))
            }
        }
    }
    report("원본", bubbleTemplate)
    report("다듬은 것", bubbleOutline)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--setup-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderSetupPreview(to: CommandLine.arguments[index + 1]))
}

if let index = CommandLine.arguments.firstIndex(of: "--render-christmas16-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderChristmas16Preview(to: CommandLine.arguments[index + 1]))
}

if let index = CommandLine.arguments.firstIndex(of: "--render-chat-font-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderPreview(to: CommandLine.arguments[index + 1], chatFonts: true))
}
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderPreview(to: CommandLine.arguments[index + 1]))
}

if let index = CommandLine.arguments.firstIndex(of: "--render-skin-preview"),
   index + 2 < CommandLine.arguments.count,
   let skin = PetSkin(rawValue: CommandLine.arguments[index + 1]) {
    exit(renderPreview(to: CommandLine.arguments[index + 2], skin: skin))
}



let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
