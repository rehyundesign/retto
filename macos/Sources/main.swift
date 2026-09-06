// 실행 진입점. 진단 플래그를 먼저 처리한다.

import AppKit
import CoreText
import Foundation

// 접근성 권한이 이 앱에 실제로 붙어 있는지. 애드혹 서명이라 다시 빌드할 때마다 풀리고,
// 손쉬운 사용 목록에는 켜져 보이는데 실제로는 없는 상태가 된다. 그때 이걸로 확인한다.
if CommandLine.arguments.contains("--ax-check") {
    print(ClaudeAppNavigator.isPermitted ? "접근성 권한: 있음" : "접근성 권한: 없음")
    exit(ClaudeAppNavigator.isPermitted ? 0 : 1)
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

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderPreview(to: CommandLine.arguments[index + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
