// 레토가 Claude Code 소식을 받고 있는지 스스로 확인한다.
//
// 있는 이유는 하나다 — 훅이 한 번도 돈 적이 없어도 레토 화면은 정상 대기와 똑같았다.
// 회색으로 자면서 "Claude Code나 Codex를 켜면 여기서 알려줄게" 라고 말한다. 고장인지
// 기다리는 중인지 구분할 방법이 없어서, 받아 간 사람이 "쳐다만 보고 있다" 고만 알려 줄 수
// 있었다. Codex 쪽에는 등록 확인이 있는데(`showCodexIntegration`) Claude 쪽에는 없었다.
//
// 여기서 보는 것은 셋이다. 훅이 등록돼 있나 · 그 훅을 돌릴 수 있나 · 소식이 실제로 오나.

import Foundation

/// 소식이 어디서 왔는지. 클라이언트마다 따로 세는 이유는, 한쪽만 동작하지 않는 일이
/// 실제로 있기 때문이다 — 터미널에서는 레토가 움직이는데 Claude 앱에서만 멈춰 있었다.
enum NewsChannel: String, CaseIterable {
    case vscode
    case claudeApp
    case cli
    case codex

    var label: String {
        switch self {
        case .vscode: return "VS Code"
        case .claudeApp: return "Claude 앱"
        case .cli: return "터미널"
        case .codex: return "Codex"
        }
    }

    /// 훅이 적어 둔 `client` 값을 채널로 옮긴다. 값이 없는 옛 기록은 셀 수 없다.
    static func of(client: String?, source: String?) -> NewsChannel? {
        if source == "codex" || client == "codex" { return .codex }
        switch client {
        case "vscode": return .vscode
        case "claude": return .claudeApp
        case "cli": return .cli
        default: return nil
        }
    }
}

struct ClaudeIntegrationStatus {
    /// settings.json 에 등록된 레토 훅 개수. 0 이면 설치가 안 됐거나 다른 것이 지웠다.
    var registeredEvents: Int = 0
    /// 그중 0.7.0 까지의 `command` + `args` 모양인 것. 이 모양은 최근 버전만 읽는다 —
    /// 데스크탑 앱이 CLI 보다 낮은 claude-code 를 쓰면 앱에서만 훅이 돌지 않는다.
    /// 하나라도 있으면 다시 깔아 `command` 한 줄로 바꿔야 한다.
    var outdatedEvents: Int = 0
    /// settings.json 을 읽을 수 있었나. JSON 이 깨져 있으면 Claude Code 도 이 파일을 못 읽는다.
    var settingsReadable: Bool = true
    /// 훅을 부르는 실행기(hook.sh)와 본체(hook.cjs)가 제자리에 있나.
    var shimInstalled: Bool = false
    var hookInstalled: Bool = false
    /// hook.sh 가 찾아낼 node. 없으면 훅이 등록돼 있어도 아무 일도 하지 않는다.
    var nodePath: String?
    /// Codex 설정에 등록된 레토 훅 개수. Claude 쪽 이벤트가 있다고 Codex 훅까지
    /// 정상이라는 뜻은 아니므로 따로 확인한다.
    var codexRegisteredEvents: Int = 0
    var codexSettingsReadable: Bool = true
    /// 설치기가 hook.cjs 를 마지막으로 복사한 시각. Codex 는 이 뒤에 새 이벤트를
    /// 한 번 받아야 현재 설치본이 실제로 실행된 것으로 본다.
    var hookUpdatedAt: Date?
    /// 채널별 마지막 소식 시각.
    var lastNews: [NewsChannel: Date] = [:]

    var hasCurrentCodexNews: Bool {
        guard let codexNews = lastNews[.codex] else { return false }
        guard let hookUpdatedAt else { return true }
        return codexNews >= hookUpdatedAt
    }

    var isHealthy: Bool {
        registeredEvents > 0 && outdatedEvents == 0
            && shimInstalled && hookInstalled && nodePath != nil && !lastNews.isEmpty
    }

    /// 메뉴에 걸 제목. 무엇이 어긋났는지 한 마디로 말한다.
    var menuTitle: String {
        let base = "AI 연동 확인"
        if !settingsReadable { return base + " — 설정 파일 문제" }
        if registeredEvents == 0 { return base + " — 훅 없음" }
        if outdatedEvents > 0 { return base + " — 훅 갱신 필요" }
        if !shimInstalled || !hookInstalled { return base + " — 훅 파일 없음" }
        if nodePath == nil { return base + " — node 없음" }
        if lastNews.isEmpty { return base + " — 소식 없음" }
        if codexRegisteredEvents > 0 && !hasCurrentCodexNews { return base + " — Codex 확인 필요" }
        return base
    }
}

enum ClaudeIntegration {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var petDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/retto-pet")
    }

    static var codexSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    /// hook.sh 가 훑는 자리와 같은 순서다. 둘이 어긋나면 여기서는 있다고 하는데
    /// 실제 훅은 node 를 못 찾는 일이 생긴다.
    static func resolveNodePath() -> String? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        candidates.append(contentsOf: [
            home + "/.volta/bin/node",
            home + "/.fnm/aliases/default/bin/node",
            home + "/Library/Application Support/fnm/aliases/default/bin/node",
            home + "/.local/share/fnm/aliases/default/bin/node",
            home + "/Library/pnpm/node",
            home + "/.asdf/shims/node"
        ])
        if let versions = try? manager.contentsOfDirectory(atPath: home + "/.nvm/versions/node") {
            candidates.append(contentsOf: versions.sorted().reversed().map { home + "/.nvm/versions/node/\($0)/bin/node" })
        }
        return candidates.first { manager.isExecutableFile(atPath: $0) }
    }

    /// settings.json 안에서 우리 훅이 몇 개인지 센다. 다른 훅의 내용은 해석하지 않는다.
    /// 0.7.0 까지의 `args` 모양과 지금의 `command` 한 줄을 함께 알아본다.
    static func countRegisteredEvents(in settings: [String: Any]) -> (total: Int, outdated: Int) {
        guard let hooks = settings["hooks"] as? [String: Any] else { return (0, 0) }
        var total = 0
        var outdated = 0
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                for handler in handlers where mentionsRetto(handler) {
                    total += 1
                    if handler["args"] is [Any] { outdated += 1 }
                }
            }
        }
        return (total, outdated)
    }

    private static func mentionsRetto(_ handler: [String: Any]) -> Bool {
        let marker = "retto-pet/hook."
        let legacyMarker = "reto-pet/hook."
        if let command = handler["command"] as? String,
           command.contains(marker) || command.contains(legacyMarker) {
            return true
        }
        if let args = handler["args"] as? [Any] {
            return args.contains { value in
                guard let text = value as? String else { return false }
                return text.contains(marker) || text.contains(legacyMarker)
            }
        }
        return false
    }

    /// Codex용 항목은 같은 hook.sh 를 호출해도 끝 인자가 `codex` 여야 한다.
    static func countRegisteredCodexEvents(in settings: [String: Any]) -> Int {
        guard let hooks = settings["hooks"] as? [String: Any] else { return 0 }
        var total = 0
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                for handler in handlers where mentionsRetto(handler) {
                    guard let command = handler["command"] as? String else { continue }
                    let parts = command.components(separatedBy: CharacterSet.whitespacesAndNewlines
                        .union(CharacterSet(charactersIn: "'\"")))
                    if parts.contains("codex") { total += 1 }
                }
            }
        }
        return total
    }

    /// 디스크에서 읽어야 아는 것들. 세션이 갱신될 때마다 메뉴 제목을 다시 짓는데,
    /// 작업 중에는 그게 1초에 여러 번이다. 설정 파일과 node 를 그때마다 훑을 이유는 없다.
    private struct DiskProbe {
        var registeredEvents = 0
        var outdatedEvents = 0
        var settingsReadable = true
        var shimInstalled = false
        var hookInstalled = false
        var nodePath: String?
        var codexRegisteredEvents = 0
        var codexSettingsReadable = true
        var hookUpdatedAt: Date?
    }

    private static var cachedProbe: (at: Date, probe: DiskProbe)?
    private static let probeInterval: TimeInterval = 5

    private static func probe(force: Bool) -> DiskProbe {
        if !force, let cached = cachedProbe, Date().timeIntervalSince(cached.at) < probeInterval {
            return cached.probe
        }
        var probe = DiskProbe()
        let manager = FileManager.default

        if let data = try? Data(contentsOf: settingsURL) {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let counted = countRegisteredEvents(in: object)
                probe.registeredEvents = counted.total
                probe.outdatedEvents = counted.outdated
            } else {
                probe.settingsReadable = false
            }
        } else if manager.fileExists(atPath: settingsURL.path) {
            probe.settingsReadable = false
        }

        probe.shimInstalled = manager.isExecutableFile(atPath: petDirectoryURL.appendingPathComponent("hook.sh").path)
        let hookURL = petDirectoryURL.appendingPathComponent("hook.cjs")
        probe.hookInstalled = manager.fileExists(atPath: hookURL.path)
        probe.hookUpdatedAt = (try? hookURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        probe.nodePath = resolveNodePath()

        if let data = try? Data(contentsOf: codexSettingsURL) {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                probe.codexRegisteredEvents = countRegisteredCodexEvents(in: object)
            } else {
                probe.codexSettingsReadable = false
            }
        } else if manager.fileExists(atPath: codexSettingsURL.path) {
            probe.codexSettingsReadable = false
        }
        cachedProbe = (Date(), probe)
        return probe
    }

    /// 방금 고친 것을 바로 보여줘야 할 때. 「훅 다시 설치」 뒤에 부른다.
    static func forgetCachedProbe() {
        cachedProbe = nil
    }

    /// 지금 상태를 모은다. 세션 목록은 앱이 이미 들고 있는 것을 그대로 받는다 —
    /// 파일을 한 번 더 읽으면 화면과 진단이 어긋날 수 있다.
    /// `fresh` 는 창을 열 때처럼 사람이 보고 있을 때만 쓴다.
    static func status(sessions: [StatePayload], fresh: Bool = false) -> ClaudeIntegrationStatus {
        let disk = probe(force: fresh)
        var status = ClaudeIntegrationStatus()
        status.registeredEvents = disk.registeredEvents
        status.outdatedEvents = disk.outdatedEvents
        status.settingsReadable = disk.settingsReadable
        status.shimInstalled = disk.shimInstalled
        status.hookInstalled = disk.hookInstalled
        status.nodePath = disk.nodePath
        status.codexRegisteredEvents = disk.codexRegisteredEvents
        status.codexSettingsReadable = disk.codexSettingsReadable
        status.hookUpdatedAt = disk.hookUpdatedAt
        status.lastNews = lastNews(in: sessions)
        return status
    }

    static func lastNews(in sessions: [StatePayload]) -> [NewsChannel: Date] {
        var latest: [NewsChannel: Date] = [:]
        for payload in sessions {
            guard let channel = NewsChannel.of(client: payload.client, source: payload.source),
                  let milliseconds = payload.updatedAtMs, milliseconds > 0 else { continue }
            let seen = Date(timeIntervalSince1970: milliseconds / 1000)
            if let known = latest[channel], known >= seen { continue }
            latest[channel] = seen
        }
        return latest
    }
}

/// "3분 전" 처럼 읽는다. 정확한 시각보다 얼마나 됐는지가 중요하다.
func elapsedLabel(since date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "방금" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)분 전" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)시간 전" }
    return "\(hours / 24)일 전"
}

/// 번들에 넣어 둔 설치기(`hook/install.cjs`)를 돌린다.
///
/// 설치·갱신·제거가 모두 이 한 곳을 지난다. 「레토 제거」와 「훅 다시 설치」가 서로 다른
/// node 를 찾으면, 한쪽은 되고 한쪽은 안 되는 상태가 만들어진다.
func runHookInstaller(arguments: [String], bundle: Bundle = .main) -> (ok: Bool, output: String) {
    guard let script = bundle.url(forResource: "install", withExtension: "cjs", subdirectory: "hook") else {
        return (false, "앱 안에서 설치기를 찾지 못했습니다")
    }
    guard let node = ClaudeIntegration.resolveNodePath() else {
        return (false, "node 를 찾지 못했습니다 — https://nodejs.org 에서 설치해 주세요")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: node)
    process.arguments = [script.path] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        // 파이프를 먼저 다 읽어야 한다. 출력이 파이프 버퍼를 넘기면 설치기가 쓰다가 멈춘다.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus == 0, text)
    } catch {
        return (false, "설치기를 실행하지 못했습니다")
    }
}
