// 세션을 어디서 열지(VS Code · Claude 앱 · Codex)와 그 딥링크.

import AppKit
import CoreText
import Foundation

enum OpenApp {
    case vscode
    case claude
    case codex

    var bundleIdentifier: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex: return "com.openai.codex"
        }
    }

    var fallbackPath: String {
        switch self {
        case .vscode: return "/Applications/Visual Studio Code.app"
        case .claude: return "/Applications/Claude.app"
        case .codex: return "/Applications/ChatGPT.app"
        }
    }

    /// VS Code 는 세션이 사는 폴더 창을 먼저 앞으로 보내야 딥링크가 그 창에 배달된다.
    /// Claude 앱은 세션이 창 하나 안에 모여 있어서 그 단계가 없다.
    var needsWindowFocusFirst: Bool { self == .vscode }

    /// 세션 하나를 콕 집어 띄우는 딥링크가 있는가.
    ///
    /// Claude 데스크탑 앱에는 없다. 앱 번들(1.37937.3)을 뜯어 확인한 것이다.
    ///   `claude://resume?session=…`        CLI 세션을 앱으로 **가져오는** 길이다.
    ///                                      `importCliSession` → `adoptCliSession` 을 부르고,
    ///                                      이미 가져온 id 로 다시 부르면 "preserved session" 이라며 던진다.
    ///                                      그래서 처음 누를 때 사본이 새 창으로 뜨고 그다음부터는 조용히 실패한다.
    ///   `claude://code/continue?session=…` 검증이 `last` 또는 `/^local_[A-Za-z0-9-]{1,64}$/` 만 받는다.
    ///                                      우리가 가진 것은 Claude Code 세션 UUID 라 걸리지 않는다.
    ///
    /// 앱을 앞으로 보내는 것까지만 한다. 세션 목록은 앱이 스스로 보여 준다.
    var hasSessionDeepLink: Bool { self != .claude }
}

let aiSessionOpenMenuTitle = "기본 열기 방식"
let emptyClaudeSessionLabel = "Claude · 실행 중인 세션 없음"
let emptyCodexSessionLabel = "Codex · 실행 중인 task 없음"

/// Codex 훅의 등록 상태는 연결 메뉴에서만 보여 준다. task를 여는 앱은 개별 task 메뉴가 정한다.
func codexOpenTargetMenuLabel(isRegistered: Bool) -> String {
    isRegistered ? "Codex 연결 확인 · 실시간 연결됨" : "Codex 연결 확인 · 기본 표시 중"
}

/// 훅이 적어 둔 클라이언트를 앱으로 옮긴다. 모르면 VS Code — 훅이 이 값을 적기 전에 시작된 세션들이다.
/// 고른 앱이 깔려 있지 않으면 다른 쪽으로 보낸다.
///
/// 받는 사람이 Claude 앱만 쓰거나 VS Code 만 쓰는 경우가 있다. 예전에는 없는 앱을 열려다
/// 삐 소리만 났다. 둘 다 없으면 고른 것을 그대로 돌려준다 — 그때는 어차피 열 수 없다.
func installedOpenApp(preferred: OpenApp, isInstalled: (OpenApp) -> Bool) -> OpenApp {
    if isInstalled(preferred) { return preferred }
    let fallbacks: [OpenApp]
    switch preferred {
    case .vscode: fallbacks = [.claude, .codex]
    case .claude: fallbacks = [.vscode, .codex]
    case .codex: fallbacks = [.claude, .vscode]
    }
    return fallbacks.first(where: isInstalled) ?? preferred
}

func openApp(forClient client: String?) -> OpenApp {
    switch client {
    case "claude": return .claude
    case "codex": return .codex
    default: return .vscode
    }
}

func sessionDeepLink(sessionId: String?, app: OpenApp) -> URL? {
    var components = URLComponents()
    switch app {
    case .vscode:
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
    case .claude:
        // 세션을 집어 띄우는 길이 없다 — `hasSessionDeepLink` 에 이유를 적어 두었다.
        return nil
    case .codex:
        guard let sessionId, !sessionId.isEmpty else { return nil }
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(sessionId)"
    }
    if app == .vscode, let sessionId, !sessionId.isEmpty {
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
    }
    return components.url
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 코덱스 배지가 쓰는 스프링 등장을 근사한다. 살짝 넘겼다가 제자리로 온다.
