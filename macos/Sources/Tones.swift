// 상태를 뜻 단위 색 넷으로 줄인 팔레트와 상태별 애니메이션.

import AppKit
import CoreText
import Foundation

// 여기에 "쉬는 중"만 무채색으로 하나 더 둔다. 색이 없어야 조용한 상태로 읽힌다.
func hexColor(_ value: UInt32) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// 레토가 누구인지. 화면 여러 곳에서 같은 값을 써야 해서 여기 모아 둔다.
enum Retto {
    /// 영어 표기는 t 를 둘 쓴다.
    static let englishName = "Retto"
    static let koreanName = "레토"
    static let character = "luxia yoon 의 랙돌 고양이"
    static let creator = "luxia yoon"
    static let email = "ydh3600@mail.com"
    static let linkedIn = "https://www.linkedin.com/in/donghyunyoon/"

    /// 실제 고양이의 신상. 화면 여러 곳에서 같은 값을 써야 하니 여기 한 벌만 둔다.
    static let breed = "랙돌"
    static let sex = "수컷"
    static let birthday = DateComponents(year: 2026, month: 2, day: 11)
    static let birthdayLabel = "2026년 2월 11일"

    /// 오늘 기준 나이. 돌 전에는 개월로만 센다 — 아직 그럴 나이다.
    static var ageLabel: String {
        let calendar = Calendar.current
        guard let born = calendar.date(from: birthday) else { return "" }
        let parts = calendar.dateComponents([.year, .month], from: born, to: Date())
        let years = max(0, parts.year ?? 0)
        let months = max(0, parts.month ?? 0)
        if years == 0 { return "\(months)개월" }
        if months == 0 { return "\(years)살" }
        return "\(years)살 \(months)개월"
    }

    /// 언제·어떤 커밋으로 만든 빌드인지. 같은 버전을 여러 번 보내도 이걸로 가른다.
    /// build.sh 가 번들 Info.plist 에만 찍으므로, 없으면 빈 문자열이다.
    static var buildStamp: String {
        Bundle.main.infoDictionary?["RettoBuildStamp"] as? String ?? ""
    }

    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return short + " (" + build + ")"
    }
}

struct StatusTone {
    let key: String
    let background: NSColor
    let text: NSColor
}

let toneWorking = StatusTone(key: "working", background: hexColor(0x73DF5D), text: hexColor(0x0A5225))
let toneNeedsYou = StatusTone(key: "needsYou", background: hexColor(0x0885FE), text: hexColor(0xFFFFFF))
// 완료 주황은 흰 글자와의 대비 때문에 한 단계만 진하게 했다(#FF7009 2.77:1 → #F06200 3.25:1).
let toneDone = StatusTone(key: "done", background: hexColor(0xF06200), text: hexColor(0xFFFFFF))
let toneFailed = StatusTone(key: "failed", background: hexColor(0xF82D39), text: hexColor(0xFFF499))
let toneQuiet = StatusTone(key: "quiet", background: hexColor(0x848484), text: hexColor(0xFFFFFF))

struct Animation {
    let row: Int
    let frames: Int
    let interval: TimeInterval
    let cycleLimit: Int?
    let kicker: String
    let title: String
    let tone: StatusTone
}

let animationCatalog: [PetState: Animation] = [
    .idle: Animation(row: 0, frames: 6, interval: 0.23, cycleLimit: nil, kicker: "RESTING", title: "조용히 곁을 지키는 중", tone: toneQuiet),
    .running: Animation(row: 7, frames: 6, interval: 0.125, cycleLimit: nil, kicker: "THINKING", title: "Claude가 생각중…", tone: toneWorking),
    .review: Animation(row: 8, frames: 6, interval: 0.155, cycleLimit: nil, kicker: "USING A TOOL", title: "도구를 쓰는 중", tone: toneWorking),
    .waiting: Animation(row: 6, frames: 6, interval: 0.31, cycleLimit: nil, kicker: "NEEDS YOU", title: "네 결정을 기다리는 중", tone: toneNeedsYou),
    .failed: Animation(row: 5, frames: 8, interval: 0.18, cycleLimit: nil, kicker: "OOPS", title: "잠깐 발이 꼬였어", tone: toneFailed),
    .waving: Animation(row: 3, frames: 4, interval: 0.185, cycleLimit: 2, kicker: "DONE", title: "다 했어! 잘했어", tone: toneDone),
    .jumping: Animation(row: 4, frames: 5, interval: 0.15, cycleLimit: nil, kicker: "LET'S GO", title: "시작해 볼까?", tone: toneWorking),
    // 행 11 은 누워 자는 레토의 한 호흡이다. 얼굴·발·바닥선은 고정하고
    // 등과 흉곽만 올라갔다 내려오며, 여섯 프레임이 약 2.76초에 한 번 돈다.
    .sleeping: Animation(row: 11, frames: 6, interval: 0.46, cycleLimit: nil, kicker: "ZZZ", title: "쿨쿨 자는 중", tone: toneQuiet)
]

/// 메뉴에서 고르는 값. `auto` 는 훅이 세션마다 적어 둔 클라이언트를 따른다.
/// VS Code 와 Claude 앱을 섞어 쓰면 고정값은 반드시 절반을 틀리므로 자동이 기본이다.
enum OpenTarget: String, CaseIterable {
    case auto
    case vscode
    case claude

    var label: String {
        switch self {
        case .auto: return "자동 · 세션이 시작된 곳"
        case .vscode: return "VS Code"
        case .claude: return "Claude 앱"
        }
    }
}

/// 실제로 띄우는 앱. `auto` 를 세션의 클라이언트로 풀어낸 결과라 여기엔 `auto` 가 없다.
