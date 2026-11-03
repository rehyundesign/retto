// 동물의 숲 대화창 윤곽. Figma 벡터를 옮겨 다듬은 경로.

import AppKit
import CoreText
import Foundation

func easeOutBack(_ t: CGFloat) -> CGFloat {
    guard t < 1 else { return 1 }
    let c: CGFloat = 1.7
    let p = t - 1
    return 1 + (c + 1) * p * p * p + c * p * p
}

/// 말풍선 윤곽. 사용자가 Figma 에서 그린 벡터(`Frame 19.svg`)의 좌표를 그대로 옮겼다.
/// 위아래로 두 번 부풀고 좌우에 허리가 들어간 구름형이라 사각형+반지름으로는 흉내낼 수 없다.
/// SVG 는 y 가 아래로 자라므로 여기서는 부호를 뒤집어 담고, 그릴 때 실제 칸에 맞춰 늘린다.
let bubbleTemplate: NSBezierPath = {
    func raw(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: -y) }
    let path = NSBezierPath()
    path.move(to: raw(158.606, 75.0158))
    path.curve(to: raw(591.263, 74.9181), controlPoint1: raw(277.269, 58.0015), controlPoint2: raw(471.57, 42.5264))
    path.curve(to: raw(591.338, 74.9181), controlPoint1: raw(591.288, 74.9181), controlPoint2: raw(591.313, 74.9181))
    path.curve(to: raw(683.57, 133.203), controlPoint1: raw(642.276, 74.9183), controlPoint2: raw(683.57, 101.013))
    path.curve(to: raw(661.497, 171.038), controlPoint1: raw(683.57, 147.643), controlPoint2: raw(675.259, 160.856))
    path.curve(to: raw(661.152, 194.693), controlPoint1: raw(658.935, 176.888), controlPoint2: raw(657.997, 184.741))
    path.line(to: raw(660.076, 194.547))
    path.curve(to: raw(663.074, 204.3), controlPoint1: raw(662.032, 197.662), controlPoint2: raw(663.074, 200.93))
    path.curve(to: raw(611.999, 238.697), controlPoint1: raw(663.074, 219.361), controlPoint2: raw(642.278, 232.396))
    path.line(to: raw(615.676, 240.159))
    path.curve(to: raw(155.133, 241.948), controlPoint1: raw(467.555, 267.445), controlPoint2: raw(255.959, 253.649))
    path.curve(to: raw(140.843, 240.212), controlPoint1: raw(150.215, 241.529), controlPoint2: raw(145.441, 240.943))
    path.curve(to: raw(140.423, 240.159), controlPoint1: raw(140.703, 240.194), controlPoint2: raw(140.562, 240.177))
    path.line(to: raw(140.459, 240.152))
    path.curve(to: raw(81.4961, 204.3), controlPoint1: raw(105.962, 234.59), controlPoint2: raw(81.4966, 220.637))
    path.curve(to: raw(84.4932, 194.547), controlPoint1: raw(81.4962, 200.93), controlPoint2: raw(82.5379, 197.661))
    path.line(to: raw(83.418, 194.693))
    path.curve(to: raw(83.0732, 171.038), controlPoint1: raw(86.5731, 184.742), controlPoint2: raw(85.6355, 176.888))
    path.curve(to: raw(61.0, 133.203), controlPoint1: raw(69.3109, 160.856), controlPoint2: raw(61.0001, 147.643))
    path.curve(to: raw(153.232, 74.9181), controlPoint1: raw(61.0006, 101.013), controlPoint2: raw(102.294, 74.9181))
    path.curve(to: raw(158.606, 75.0158), controlPoint1: raw(155.036, 74.9181), controlPoint2: raw(156.828, 74.9512))
    path.close()
    return path
}()

/// 원본 벡터에는 곡선 사이에 아주 짧은 직선 조각이 끼어 있어(예: `L660.076 194.547`) 그 자리에서
/// 접선이 꺾인다. 윤곽을 같은 간격으로 다시 뽑아 이동평균으로 다듬고 Catmull-Rom 으로 이어 붙이면
/// 꺾임이 사라지고 옆으로 부푼 두 덩이가 더 둥글어진다. 다듬는 횟수가 곧 둥글기다.
func smoothedClosedPath(from source: NSBezierPath, samples: Int, passes: Int) -> NSBezierPath {
    // 1) 윤곽을 잘게 펴서 점으로 만든다
    let flat = source.flattened
    var raw: [NSPoint] = []
    var element = [NSPoint](repeating: .zero, count: 3)
    for index in 0..<flat.elementCount {
        switch flat.element(at: index, associatedPoints: &element) {
        case .moveTo, .lineTo: raw.append(element[0])
        case .closePath: break
        default: break
        }
    }
    guard raw.count > 8 else { return source }

    // 2) 둘레를 따라 같은 간격으로 다시 뽑는다
    var lengths: [CGFloat] = [0]
    for index in 1...raw.count {
        let a = raw[index - 1], b = raw[index % raw.count]
        lengths.append(lengths[index - 1] + hypot(b.x - a.x, b.y - a.y))
    }
    let perimeter = lengths[raw.count]
    guard perimeter > 0 else { return source }
    var points: [NSPoint] = []
    var cursor = 0
    for step in 0..<samples {
        let target = perimeter * CGFloat(step) / CGFloat(samples)
        while cursor < raw.count - 1 && lengths[cursor + 1] < target { cursor += 1 }
        let a = raw[cursor], b = raw[(cursor + 1) % raw.count]
        let span = lengths[cursor + 1] - lengths[cursor]
        let t = span > 0 ? (target - lengths[cursor]) / span : 0
        points.append(NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }

    // 3) 이동평균으로 다듬는다 (닫힌 곡선이므로 앞뒤가 이어진다)
    for _ in 0..<passes {
        var next = points
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let following = points[(index + 1) % points.count]
            next[index] = NSPoint(
                x: (previous.x + 2 * current.x + following.x) / 4,
                y: (previous.y + 2 * current.y + following.y) / 4
            )
        }
        points = next
    }

    // 4) Catmull-Rom 을 3차 베지에로 바꿔 이어 붙인다
    let path = NSBezierPath()
    path.move(to: points[0])
    for index in points.indices {
        let p0 = points[(index - 1 + points.count) % points.count]
        let p1 = points[index]
        let p2 = points[(index + 1) % points.count]
        let p3 = points[(index + 2) % points.count]
        path.curve(
            to: p2,
            controlPoint1: NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
            controlPoint2: NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        )
    }
    path.close()
    return path
}

/// 다듬은 윤곽. 한 번만 만들어 두고 칸에 맞춰 늘려 쓴다.
let bubbleOutline = smoothedClosedPath(from: bubbleTemplate, samples: 160, passes: 6)

/// 원본 도형을 주어진 칸에 꽉 채워 넣는다. 도형 자체의 경계를 기준으로 재므로 여백이 남지 않는다.
func bubblePath(in rect: NSRect) -> NSBezierPath {
    guard let path = bubbleOutline.copy() as? NSBezierPath else { return NSBezierPath(rect: rect) }
    let bounds = path.bounds
    guard bounds.width > 0, bounds.height > 0 else { return path }
    var transform = AffineTransform(translationByX: rect.minX, byY: rect.minY)
    transform.scale(x: rect.width / bounds.width, y: rect.height / bounds.height)
    transform.translate(x: -bounds.minX, y: -bounds.minY)
    path.transform(using: transform)
    return path
}

