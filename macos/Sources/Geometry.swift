// 레토와 말풍선의 크기·자리 계산. 배율 하나가 몸과 말풍선으로 갈리는 곳.

import AppKit
import CoreText
import Foundation

// 칸은 몸보다 넓다. 남는 좌우 여백은 스킨의 날개가 쓴다 — 여백이 없으면 날개를 달려고
// 고양이를 줄여야 했다. 여백은 투명이라 hitTest 가 클릭을 통과시킨다.
let cellWidth: CGFloat = 224
// 칸은 머리 위로도 여유를 둔다. 스킨의 후드 귀나 날개 끝이 여기로 들어간다.
let cellHeight: CGFloat = 240
let sheetWidth: CGFloat = 1792
let sheetHeight: CGFloat = 2880
let rettoHandwritingFontName = "NanumMiNiSonGeurSsi"

/// 말풍선에 쓸 글꼴. 손글씨가 기본이고, 읽기 힘들면 시스템 서체로 바꾼다.
/// 끌고 갈 때 달리는 방향. 화면 기준이다.
enum DragRun {
    case right
    case left
}

/// 레토의 겉모습. 아틀라스 파일을 통째로 갈아 끼운다.
/// 스킨마다 칸 규격(224x240, 8x12)은 같아야 한다 — 그리는 자리 계산이 공용이다.
enum PetSkin: String, CaseIterable {
    case classic
    case angelWings
    case rilakkuma

    var label: String {
        switch self {
        case .classic: return "기본"
        case .angelWings: return "천사 날개"
        case .rilakkuma: return "리락쿠마"
        }
    }

    /// 번들 안 리소스 이름. 확장자는 webp 로 고정이다.
    var resourceName: String {
        switch self {
        case .classic: return "spritesheet"
        case .angelWings: return "spritesheet-angel"
        case .rilakkuma: return "spritesheet-rilakkuma"
        }
    }

    /// 만든 사람만 쓰는 스킨. 아틀라스를 레포에도 배포 묶음에도 넣지 않는다.
    /// 받아 간 쪽에서는 파일이 없으므로 메뉴에 자물쇠로 뜨고 고를 수 없다.
    var isPersonal: Bool {
        switch self {
        case .rilakkuma: return true
        default: return false
        }
    }

    /// 이 기기의 앱 번들에 아틀라스가 실제로 들어 있는지.
    var isAvailable: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "webp") != nil
    }
}

enum PetTypeface: String, CaseIterable {
    case handwriting
    case system

    var label: String {
        switch self {
        case .handwriting: return "손글씨체"
        case .system: return "기본 서체"
        }
    }
}

/// 기본 서체는 같은 pt 에서 손글씨보다 크게 보인다 — 속공간이 넓어서다. 4.5pt 낮춰 눈에 맞춘다.
let systemTypefaceDelta: CGFloat = -4.5

/// 손글씨 등록이 실패해도 시스템 서체로 떨어져 글자가 사라지지 않는다.
func petFont(_ typeface: PetTypeface, size: CGFloat, bold: Bool = false) -> NSFont {
    if typeface == .handwriting, let font = NSFont(name: rettoHandwritingFontName, size: size) {
        return font
    }
    let systemSize = max(1, size + systemTypefaceDelta)
    return bold ? NSFont.boldSystemFont(ofSize: systemSize) : NSFont.systemFont(ofSize: systemSize)
}

// 레토 몸과 상태 리본은 따로 자란다. 몸은 고른 배율을 그대로 따르고,
// 리본은 글자가 읽히는 최소 배율(chromeScaleFloor) 아래로는 줄지 않는다.
// 창은 둘 중 넓은 쪽에 맞추므로 작은 배율에서는 몸보다 창이 넓어진다.
// 칸이 192 에서 224 로 넓어진 만큼 같이 키운다(252 × 224/192). 화면에 보이는 몸 크기는 그대로다.
let basePetWidth: CGFloat = 294
// 칸 자체가 좌우 16px 씩 여백을 갖게 되어 창 여백은 그만큼 줄인다. 창 폭 306 은 그대로다.
let petSideMargin: CGFloat = 6
let petBadgeHeadroom: CGFloat = 26
// 동물의 숲 대화창 비례. 이름표가 말풍선 위로 솟으므로 레토와 말풍선 사이를 띄운다.
let petRibbonOverlap: CGFloat = -4
let baseRibbonWidth: CGFloat = 280
// 본문 18pt 한 줄이 20.70pt(ascender 16.56 + descender 4.14). 줄간 0.875 로 두 줄이면 42.28pt,
// 상하 여백 30 을 더해 75 면 넉넉히 들어간다. 세 줄(63.9+30=94)은 안 들어가므로 두 줄에서 … 로 접힌다.
let baseRibbonHeight: CGFloat = 75
let ribbonSideInset: CGFloat = 13
let ribbonBottomInset: CGFloat = 12
// 말풍선·이름표·배지 배율. 레토 배율에 **항상** 비례해 커지되, 기울기를 눌러 글이 읽히는 크기를 지킨다.
//   chromeScaleAtMin = 가장 작은 프리셋(35%)에서의 말풍선 배율
//   chromeScaleSlope = 레토가 1 커질 때 말풍선이 커지는 정도
// max(배율, 하한) 로 두면 하한 아래 프리셋이 전부 같은 크기로 뭉개진다(65% 와 80% 가 같아짐).
// 두 점을 지나도록 잡았다 — 35%(초소형) 본문 16.9pt, 50% 본문 19.6pt.
let chromeScaleAtMin: CGFloat = 0.941
let chromeScaleSlope: CGFloat = 0.987

/// 곡선의 기준점. 프리셋 목록과 따로 둔다 — `supportedScales.first` 를 쓰면 초소형 프리셋만
/// 손봐도 기준이 따라 움직여 50%·65% 의 말풍선까지 덩달아 줄어든다.
let chromeScaleAnchor: CGFloat = 0.35

func chromeScale(for scale: CGFloat) -> CGFloat {
    min(2.4, chromeScaleAtMin + (scale - chromeScaleAnchor) * chromeScaleSlope)
}

/// 프리셋별로 글자만 따로 깎는 값(pt). 말풍선 크기·여백은 그대로 두고 글씨만 줄인다.
/// 곡선을 다시 맞추면 프리셋 여덟 개가 전부 따라 움직이므로, 한 프리셋만 손볼 때는 여기서 뺀다.
/// 50%: 본문 19.6pt·이름표 18.0pt 가 126pt 짜리 몸 옆에서 커 보인다. 1.5pt 씩 깎아 18.1pt·16.5pt 로 둔다.
let chromeTextDeltas: [(scale: CGFloat, delta: CGFloat)] = [(0.39, -0.5), (0.5, -1.5)]

func chromeTextDelta(for scale: CGFloat) -> CGFloat {
    chromeTextDeltas.first { abs($0.scale - scale) < 0.001 }?.delta ?? 0
}
/// 말풍선을 펼쳤을 때 본문에 더 주는 높이. 9.5pt 세 줄 + 여백.
let ribbonBodyHeight: CGFloat = 44
let ribbonExpandDelay: TimeInterval = 0.3
/// 이름표 폭의 기준. 한글 이 글자 수만큼의 폭을 재서 상한으로 쓴다.
/// 글자 수로 자르면 폭이 좁은 영문이 12자에서 억울하게 잘린다. 그래서 폭으로만 판단한다.
let sectionLabelWidthSample = String(repeating: "가", count: 12)
/// 이름표 높이 중 말풍선 안으로 들어가는 비율.
let namePillOverlap: CGFloat = 0.45
let seenSessionsDefaultsKey = "RettoClaudePetSeenSessions"
let cornerDefaultsKey = "RettoClaudePetCorner"
let followClaudeDefaultsKey = "RettoPetFollowClaudeSession"
let accessibilityAskedDefaultsKey = "RettoPetAskedAccessibility"
let openTargetDefaultsKey = "RettoClaudePetOpenTarget"
let typefaceDefaultsKey = "RettoClaudePetTypeface"
let clickThroughNoticeDefaultsKey = "RettoClaudePetClickThroughNoticeSeen"
let skinDefaultsKey = "RettoClaudePetSkin"
// 배지 지름과 흰 테두리. 이름표 오른쪽 위 모서리에 살짝 겹쳐 앉는다.
let attentionBadgeSide: CGFloat = 20
/// 이름표와 배지가 같이 쓰는 흰 테두리 두께.
func chromeStrokeWidth(_ scale: CGFloat) -> CGFloat { max(0.75, 1.1 * scale) }
// 초소형은 35% 였는데 레토가 너무 작아 39% 로 올렸다. 말풍선 기준점(chromeScaleAnchor)은
// 35% 에 그대로 두었으므로 다른 프리셋의 말풍선 크기는 변하지 않는다.
let supportedScales: [CGFloat] = [0.39, 0.5, 0.65, 0.8, 1.0, 1.2, 1.4]

struct PetLayout {
    let windowSize: NSSize
    let petRect: NSRect
    let ribbonRect: NSRect
    let petScale: CGFloat
    let chromeScale: CGFloat
    /// 이름표·본문 글자 크기에 더하는 pt. 말풍선 치수에는 쓰지 않는다.
    let textDelta: CGFloat
    let isExpanded: Bool
}

func petLayout(scale: CGFloat, width overrideWidth: CGFloat? = nil, expanded: Bool = false) -> PetLayout {
    let chromeScale = chromeScale(for: scale)
    let petWidth = basePetWidth * scale
    let petHeight = petWidth * cellHeight / cellWidth
    // 펼치면 말풍선만 아래로 자란다. 레토와 배지의 자리는 그대로 둔다.
    let ribbonHeight = (baseRibbonHeight + (expanded ? ribbonBodyHeight : 0)) * chromeScale
    let canonicalWidth = max(petWidth + 2 * petSideMargin * scale, (baseRibbonWidth + 2 * ribbonSideInset) * chromeScale)
    let width = overrideWidth ?? canonicalWidth
    let petBottom = ribbonBottomInset * chromeScale + ribbonHeight - petRibbonOverlap * scale
    let windowHeight = petBottom + petHeight + petBadgeHeadroom * scale
    let petRect = NSRect(x: (width - petWidth) / 2, y: petBottom, width: petWidth, height: petHeight)
    return PetLayout(
        windowSize: NSSize(width: canonicalWidth, height: windowHeight),
        petRect: petRect,
        ribbonRect: NSRect(
            x: ribbonSideInset * chromeScale,
            y: ribbonBottomInset * chromeScale,
            width: width - 2 * ribbonSideInset * chromeScale,
            height: ribbonHeight
        ),
        petScale: scale,
        chromeScale: chromeScale,
        textDelta: chromeTextDelta(for: scale),
        isExpanded: expanded
    )
}

/// 배지는 말풍선 오른쪽 위에 고정으로 걸터앉는다. 왼쪽 이름표와 같은 높이·같은 겹침이라 좌우 대칭이다.
/// 이름표에 붙이면 세션 제목 길이에 따라 자리가 흔들려서 눈이 한 곳을 못 잡는다.
func attentionBadgeRect(ribbon: NSRect, scale: CGFloat) -> NSRect {
    let side = attentionBadgeSide * scale
    return NSRect(
        x: ribbon.maxX - 14 * scale - side,
        y: ribbon.maxY - side * namePillOverlap,
        width: side,
        height: side
    )
}

enum PetClickTarget {
    case badge
    case body
    case ribbon
}

/// 창의 어느 지점이 무엇을 누른 것인지 정한다. 배지가 있을 때만 배지가 몸통보다 앞선다.
/// 코덱스 펫처럼 몸통 클릭은 반응(점프)으로 끝내고, 세션을 여는 건 말풍선과 배지가 맡는다.
func petClickTarget(layout: PetLayout, badgeFrame: NSRect, point: NSPoint, attentionCount: Int) -> PetClickTarget? {
    if attentionCount > 0 && !badgeFrame.isEmpty && badgeFrame.contains(point) { return .badge }
    if layout.ribbonRect.contains(point) { return .ribbon }
    if layout.petRect.contains(point) { return .body }
    return nil
}

/// 코덱스 펫은 idle·running·waving 에서만 시선을 따라간다. 나머지 상태에서는 자기 애니메이션을 지킨다.
let gazeStates: Set<PetState> = [.idle, .running, .waving]

/// 레토를 화면 어디에 둘지. 자유 위치는 끌어다 놓은 자리를 그대로 쓴다.
enum PetCorner: String, CaseIterable {
    case free
    case bottomRight
    case topRight
    case topLeft
    case bottomLeft

    var label: String {
        switch self {
        case .free: return "자유 위치 · 끌어서 옮기기"
        case .bottomRight: return "우측 하단 고정"
        case .topRight: return "우측 상단 고정"
        case .topLeft: return "좌측 상단 고정"
        case .bottomLeft: return "좌측 하단 고정"
        }
    }

    /// 아래쪽에 붙는 모서리인가. 말풍선이 펼쳐질 때 어느 변을 고정할지 정한다.
    var anchorsToBottom: Bool { self == .bottomRight || self == .bottomLeft }
}

/// 화면 가장자리에서 띄우는 간격.
let petCornerMargin: CGFloat = 24

/// 고정된 모서리에서의 창 왼쪽 아래 좌표. 자유 위치면 nil 이다.
func cornerOrigin(corner: PetCorner, size: NSSize, visible: NSRect) -> NSPoint? {
    guard corner != .free else { return nil }
    let x: CGFloat
    switch corner {
    case .topLeft, .bottomLeft: x = visible.minX + petCornerMargin
    default: x = visible.maxX - size.width - petCornerMargin
    }
    let y: CGFloat
    switch corner {
    case .topLeft, .topRight: y = visible.maxY - size.height - petCornerMargin
    default: y = visible.minY + petCornerMargin
    }
    return NSPoint(x: x, y: y)
}
