// 실행 진입점. 진단 플래그를 먼저 처리한다.

import AppKit
import CoreText
import Foundation

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
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

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
    exit(renderPreview(to: CommandLine.arguments[index + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
