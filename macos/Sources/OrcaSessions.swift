// Orca 에서 띄운 세션을 알아보고, 누르면 Orca 의 그 탭으로 데려간다.
//
// Orca 는 Claude Code·Codex 를 자기 채팅 탭이나 터미널 탭 안에서 띄운다. 레토는 예전부터 그 소식을
// 받고 있었지만 어디서 왔는지 몰라서, Claude 채팅은 Claude 앱으로, Codex 채팅은 Codex 앱으로 보냈다.
//
// 어떻게 알아보나
//   Claude 채팅  훅이 `CLAUDE_CODE_ENTRYPOINT=orca` 와 `ORCA_AGENT_SESSION_ID` 를 받아 적는다.
//   터미널 탭    훅이 `ORCA_TERMINAL_HANDLE` 을 받아 적는다.
//   Codex 채팅   Orca 는 자기가 띄운 Codex 의 `~/.codex/hooks.json` 훅을 끈다(`-c hooks.state=…`).
//                그래서 롤아웃 첫 줄(session_meta)의 `originator: "orca_desktop"` 으로 판정한다.
//
// 어떻게 데려가나
//   `orca://` 링크는 페어링·플러그인용뿐이고, `orca` CLI 에도 채팅 탭을 고르는 명령이 없다.
//   CLI 가 쓰는 런타임 클라이언트로 Orca 에 직접 요청한다 — 탭 목록(`session.tabs.listAll`)에서
//   그 채팅을 찾고, 워크스페이스를 연 뒤(`worktree.activate`) 탭을 고른다(`session.tabs.activate`).
//   터미널 탭과 워크스페이스는 공개 CLI(`terminal switch`·`worktree activate`)를 쓴다.
//   Orca 내부 모듈이라 업데이트로 바뀔 수 있다. 실패하면 워크스페이스까지만 열고, 그것도 안 되면
//   Orca 를 앞으로 가져오는 것으로 끝낸다.

import AppKit
import Foundation

let orcaBundleIdentifier = "com.stablyai.orca"

/// Codex 롤아웃 첫 줄이 Orca 채팅이 띄운 스레드의 것인가.
func codexSessionMetaIsFromOrca(_ firstLine: String) -> Bool {
    guard let data = firstLine.data(using: .utf8),
          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let payload = record["payload"] as? [String: Any] else { return false }
    return payload["originator"] as? String == "orca_desktop"
}

/// 롤아웃 경로마다 한 번만 첫 줄을 읽는다. originator 는 스레드가 생길 때 정해지고 바뀌지 않는다.
final class OrcaCodexOriginReader {
    private var cache: [String: Bool] = [:]

    func isFromOrca(transcriptPath path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        if let cached = cache[path] { return cached }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        // session_meta 첫 줄에는 기본 지시문이 함께 들어가 16KB 를 넘는다. 롤아웃 탐색과 같은 범위를 읽는다.
        guard let data = try? handle.read(upToCount: 512 * 1024),
              let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\n", maxSplits: 1).first else { return false }
        let result = codexSessionMetaIsFromOrca(String(firstLine))
        if cache.count >= 1024 { cache.removeAll(keepingCapacity: true) }
        cache[path] = result
        return result
    }
}

/// Orca 에 무엇을 열어 달라고 할지.
struct OrcaOpenRequest: Equatable {
    /// Orca 채팅 세션 ID(`claude_…`·`codex_…`). 탭 ID 는 `agent-session:` 을 앞에 붙인 값이다.
    var sessionId: String?
    var terminalHandle: String?
    /// 세션의 작업 폴더. 채팅 ID 를 모를 때(훅 없는 Codex) 그 워크스페이스의 채팅 탭을 찾는 데 쓴다.
    var workspacePath: String?
    /// `claude` · `codex`. 한 워크스페이스에 두 종류 채팅이 있으면 맞는 쪽만 고른다.
    var agent: String
}

func orcaOpenRequest(for payload: StatePayload) -> OrcaOpenRequest? {
    guard payload.isOrca, payload.source != "slack" else { return nil }
    func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
    return OrcaOpenRequest(
        sessionId: nonEmpty(payload.orcaSessionId),
        terminalHandle: nonEmpty(payload.orcaTerminalHandle),
        workspacePath: nonEmpty(payload.cwd),
        agent: payload.source == "codex" || payload.client == "codex" ? "codex" : "claude"
    )
}

enum OrcaOpenOutcome: String {
    case chat
    case terminal
    case workspace
    /// Orca 를 앞으로 가져오기만 했다.
    case app
    case unavailable
}

/// Orca 의 Electron 을 node 로 띄워 돌리는 짧은 스크립트. 요청은 환경변수 `RETTO_ORCA_REQUEST` 로 받고,
/// 결과를 JSON 한 줄(`{"opened":"chat"}` 등)로 출력한다. 화면을 바꾸는 요청만 보내고 대화 내용은 읽지 않는다.
let orcaRevealScript = #"""
const request = JSON.parse(process.env.RETTO_ORCA_REQUEST || '{}');
const print = (value) => process.stdout.write(JSON.stringify(value) + '\n');
const pathOf = (worktree) => String(worktree || '').split('::').slice(1).join('::');
(async () => {
  const { RuntimeClient } = require(request.clientPath);
  const client = new RuntimeClient(undefined, undefined, null, null);
  const call = async (method, params) => {
    const response = await client.call(method, params);
    if (!response || response.ok === false) throw new Error(method);
    return response.result;
  };
  const snapshots = ((await call('session.tabs.listAll', {})) || {}).snapshots || [];
  const chats = [];
  for (const snapshot of snapshots) {
    for (const tab of snapshot.tabs || []) {
      if (tab.type === 'agent-session' && tab.sessionId) {
        chats.push({ worktree: snapshot.worktree, tabId: tab.id, sessionId: tab.sessionId, agent: tab.agent });
      }
    }
  }
  let chat = request.sessionId ? chats.find((item) => item.sessionId === request.sessionId) : undefined;
  if (!chat && !request.sessionId && request.workspacePath) {
    const candidates = chats.filter((item) => pathOf(item.worktree) === request.workspacePath
      && (!request.agent || item.agent === request.agent));
    // 같은 워크스페이스에 같은 종류 채팅이 여럿이면 어느 것인지 모른다. 워크스페이스까지만 연다.
    if (candidates.length === 1) chat = candidates[0];
  }
  if (!chat) {
    const workspace = snapshots.find((snapshot) => pathOf(snapshot.worktree) === request.workspacePath);
    if (!workspace) return print({ opened: 'none' });
    await call('worktree.activate', { worktree: 'id:' + workspace.worktree, navigation: 'host' });
    return print({ opened: 'workspace' });
  }
  const worktree = 'id:' + chat.worktree;
  await call('worktree.activate', { worktree, navigation: 'host' });
  await call('session.tabs.activate', { worktree, tabId: chat.tabId, navigation: 'host', intent: 'user' });
  print({ opened: 'chat' });
})().catch((error) => {
  print({ opened: 'error', message: String((error && error.message) || error).slice(0, 200) });
  process.exitCode = 1;
}).finally(() => setTimeout(() => process.exit(), 20));
"""#

final class OrcaNavigator {
    private let queue = DispatchQueue(label: "retto.orca-navigator", qos: .userInitiated)

    var appURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: orcaBundleIdentifier) { return url }
        let fallback = URL(fileURLWithPath: OpenApp.orca.fallbackPath)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    /// Orca 를 앞으로 가져오고 그 세션의 탭을 고른다. completion 은 메인 스레드에서 부른다.
    func open(_ request: OrcaOpenRequest, completion: @escaping (OrcaOpenOutcome) -> Void) {
        guard let appURL else {
            completion(.unavailable)
            return
        }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: orcaBundleIdentifier).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            guard let self else { return }
            if error != nil {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }
            // 막 켠 Orca 는 런타임이 뜰 때까지 요청을 받지 못한다.
            self.queue.asyncAfter(deadline: .now() + (wasRunning ? 0 : 4)) {
                let outcome = self.navigate(request, appURL: appURL)
                DispatchQueue.main.async { completion(outcome) }
            }
        }
    }

    private func navigate(_ request: OrcaOpenRequest, appURL: URL) -> OrcaOpenOutcome {
        let resources = appURL.appendingPathComponent("Contents/Resources")
        let cli = resources.appendingPathComponent("bin/orca")
        if let handle = request.terminalHandle,
           run(cli, ["terminal", "switch", "--terminal", handle, "--json"]) != nil {
            return .terminal
        }
        let clientPath = resources.appendingPathComponent("app.asar.unpacked/out/cli/runtime-client.js").path
        if request.sessionId != nil || request.workspacePath != nil,
           FileManager.default.fileExists(atPath: clientPath) {
            var body: [String: String] = ["clientPath": clientPath, "agent": request.agent]
            if let sessionId = request.sessionId { body["sessionId"] = sessionId }
            if let path = request.workspacePath { body["workspacePath"] = path }
            if let json = try? JSONSerialization.data(withJSONObject: body),
               let encoded = String(data: json, encoding: .utf8),
               let output = run(appURL.appendingPathComponent("Contents/MacOS/Orca"), ["-e", orcaRevealScript],
                                extraEnvironment: ["ELECTRON_RUN_AS_NODE": "1", "RETTO_ORCA_REQUEST": encoded]),
               let opened = orcaRevealOutcome(output) {
                return opened
            }
        }
        // 내부 요청이 안 되면 공개 CLI 로 워크스페이스까지만 연다.
        if let path = request.workspacePath,
           run(cli, ["worktree", "activate", "--worktree", "path:\(path)", "--json"]) != nil {
            return .workspace
        }
        return .app
    }

    /// 끝나면 표준 출력을, 실패하거나 8초 안에 끝나지 않으면 nil 을 돌려준다.
    private func run(_ executable: URL, _ arguments: [String], extraEnvironment: [String: String] = [:]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // 레토를 Orca 터미널에서 켰더라도 원격 Orca 나 다른 프로필로 가지 않게 Orca 변수는 넘기지 않는다.
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("ORCA_") && $0.key != "NODE_OPTIONS" && $0.key != "ELECTRON_RUN_AS_NODE"
        }
        if environment["PATH"] == nil { environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin" }
        for (key, value) in extraEnvironment { environment[key] = value }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        // 출력이 파이프 버퍼를 넘어도 막히지 않게 끝날 때까지 읽는다.
        var data = Data()
        let reader = DispatchQueue(label: "retto.orca-navigator.read")
        reader.async { data = output.fileHandleForReading.readDataToEndOfFile() }
        if finished.wait(timeout: .now() + 8) == .timedOut {
            process.terminate()
            return nil
        }
        reader.sync {}
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 스크립트가 마지막 줄에 출력한 결과를 읽는다. 아무것도 못 열었으면 nil.
func orcaRevealOutcome(_ output: String) -> OrcaOpenOutcome? {
    guard let line = output.split(separator: "\n").last,
          let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    switch object["opened"] as? String {
    case "chat": return .chat
    case "workspace": return .workspace
    default: return nil
    }
}
