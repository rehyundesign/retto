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

    private func run(_ executable: URL, _ arguments: [String], extraEnvironment: [String: String] = [:]) -> String? {
        runOrcaProcess(executable, arguments, extraEnvironment: extraEnvironment)
    }
}

/// 끝나면 표준 출력을, 실패하거나 제한 시간 안에 끝나지 않으면 nil 을 돌려준다.
func runOrcaProcess(_ executable: URL, _ arguments: [String], extraEnvironment: [String: String] = [:],
                    timeout: TimeInterval = 8) -> String? {
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
    let reader = DispatchQueue(label: "retto.orca-process.read")
    reader.async { data = output.fileHandleForReading.readDataToEndOfFile() }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        return nil
    }
    reader.sync {}
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8) ?? ""
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

// MARK: - Orca 의 Codex 채팅이 내 답을 기다리는지
//
// Orca 는 자기가 띄운 Codex 의 훅을 끄므로 레토 훅으로는 승인·질문 대기를 알 수 없다. 롤아웃에도
// 승인 요청은 남지 않는다(도구 호출만 남고 결과가 안 붙은 채로 멈춰 있어 오래 걸리는 명령과 구분이 안 된다).
// 대신 Orca 가 그 채팅 탭에 붙여 두는 상태(`session.tabs.listAll` 의 `chatStatus`)를 읽는다.
// Orca 1.4.257 은 승인·질문이 걸려 있거나 턴이 사용자 답을 기다리며 끝나면 `blocked` 를,
// 터미널 훅 경로에서는 `waiting` 을 쓴다. 실패는 `done` + `outcome: failure` 라 `blocked` 와 겹치지 않는다
// (2026-11-13 실측: 「ask」 권한 채팅에서 권한 상승 명령을 시키자 `working` → `blocked`).
//
// 탭에는 Codex 스레드 ID 가 없어서, Orca 세션 기록(`agent-session-journal.db` 의 `providerHandleChain`)을
// 읽기 전용으로 열어 Orca 세션 ID 와 잇는다. 이을 수 없는 채팅은 추측하지 않고 버린다 — 다른 스레드를
// 파랗게 칠하는 것보다 대기를 놓치는 편이 낫다. 기록을 쓰거나 응답을 보내지 않는다.

/// Orca 채팅 탭 하나의 상태. `threadId` 는 Codex 스레드(= 롤아웃 파일 이름의 UUID)다.
struct OrcaChatStatus: Equatable {
    let orcaSessionId: String
    let threadId: String
    /// Orca 가 이 채팅을 내 답을 기다리는 상태로 표시했나.
    let needsInput: Bool
    /// 지금 상태가 시작된 시각(ms).
    let sinceMs: Double
}

let orcaChatStatusScript = #"""
const request = JSON.parse(process.env.RETTO_ORCA_REQUEST || '{}');
const print = (value) => process.stdout.write(JSON.stringify(value) + '\n');
(async () => {
  const runtime = require(request.clientPath);
  const client = new runtime.RuntimeClient(undefined, undefined, null, null);
  const response = await client.call('session.tabs.listAll', {});
  if (!response || response.ok === false) throw new Error('session.tabs.listAll');
  const chats = [];
  for (const snapshot of (response.result || {}).snapshots || []) {
    for (const tab of snapshot.tabs || []) {
      if (tab.type === 'agent-session' && tab.agent === 'codex' && tab.sessionId && tab.chatStatus) {
        chats.push({ sessionId: tab.sessionId, status: tab.chatStatus });
      }
    }
  }
  const threads = {};
  if (chats.length > 0) {
    const { DatabaseSync } = require('node:sqlite');
    const home = (runtime.getDefaultUserDataPath && runtime.getDefaultUserDataPath()) || request.userDataPath;
    const db = new DatabaseSync(require('path').join(home, 'agent-session-journal.db'), { readOnly: true });
    try {
      const query = db.prepare('SELECT record_json FROM agent_session_records WHERE session_id = ?');
      for (const chat of chats) {
        const row = query.get(chat.sessionId);
        if (!row) continue;
        const chain = (JSON.parse(row.record_json) || {}).providerHandleChain || [];
        const handle = [...chain].reverse().map((link) => link && link.handle)
          .find((value) => value && value.provider === 'codex' && value.threadId);
        if (handle) threads[chat.sessionId] = handle.threadId;
      }
    } finally {
      db.close();
    }
  }
  print({ chats: chats.map(({ sessionId, status }) => {
    const main = status.mainAgent || {};
    return {
      sessionId,
      threadId: threads[sessionId] || null,
      state: status.state,
      since: main.state === status.state && main.stateStartedAt ? main.stateStartedAt : status.updatedAt,
    };
  }) });
})().catch((error) => {
  print({ error: String((error && error.message) || error).slice(0, 200) });
  process.exitCode = 1;
}).finally(() => setTimeout(() => process.exit(), 20));
"""#

/// 스크립트 출력에서 Codex 스레드별 상태를 고른다. 출력을 못 읽으면 nil — 「대기 없음」과 구분한다.
func orcaChatStatuses(fromOutput output: String) -> [String: OrcaChatStatus]? {
    guard let line = output.split(separator: "\n").last,
          let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let chats = object["chats"] as? [[String: Any]] else { return nil }
    func identifier(_ value: Any?) -> String? {
        guard let text = value as? String,
              text.range(of: "^[A-Za-z0-9_:.-]{1,128}$", options: .regularExpression) != nil else { return nil }
        return text
    }
    var result: [String: OrcaChatStatus] = [:]
    for chat in chats {
        guard let sessionId = identifier(chat["sessionId"]), let threadId = identifier(chat["threadId"]),
              let state = chat["state"] as? String else { continue }
        let status = OrcaChatStatus(orcaSessionId: sessionId, threadId: threadId,
                                    needsInput: state == "blocked" || state == "waiting",
                                    sinceMs: (chat["since"] as? Double) ?? 0)
        // 한 스레드를 두 탭이 가리키면(포크 직후 등) 어느 쪽인지 모른다. 둘 다 버린다.
        if result[threadId] != nil {
            result[threadId] = OrcaChatStatus(orcaSessionId: "", threadId: threadId, needsInput: false, sinceMs: 0)
        } else {
            result[threadId] = status
        }
    }
    return result.filter { !$0.value.orcaSessionId.isEmpty }
}

/// Orca 가 알려 준 채팅 상태를 화면 상태에 겹친다. 대기가 아니면 롤아웃이 정한 상태를 그대로 둔다.
func applyOrcaChatStatus(_ chat: OrcaChatStatus?, to payload: StatePayload) -> StatePayload {
    guard let chat else { return payload }
    var result = payload
    if (result.orcaSessionId ?? "").isEmpty { result.orcaSessionId = chat.orcaSessionId }
    guard chat.needsInput else { return result }
    // 다음 조회 전에 롤아웃이 턴이 끝났다고 먼저 알려 왔으면 지난 대기를 다시 띄우지 않는다.
    let inTurn = result.petState == .running || result.petState == .review || result.petState == .waiting
    if !inTurn, (result.updatedAtMs ?? 0) > chat.sinceMs { return result }
    result.state = PetState.waiting.rawValue
    result.attention = true
    if chat.sinceMs > 0 { result.updatedAtMs = chat.sinceMs }
    result.stateSource = "orca"
    return result
}

/// 일하는 중인 Orca 의 Codex 채팅만 몇 초마다 Orca 에 물어본다. 묻는 동안 Orca 를 켜지 않는다.
/// 한 번에 Orca 의 Electron 을 node 로 0.3초쯤 띄운다(2026-11-13 측정: 0.29초, 최대 메모리 89MB).
final class OrcaChatStatusReader {
    static let interval: TimeInterval = 3
    /// Codex 스레드 ID → 상태. 메인 스레드에서만 읽고 쓴다.
    private(set) var statuses: [String: OrcaChatStatus] = [:]
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "retto.orca-chat-status", qos: .utility)
    private var timer: Timer?
    private var inFlight = false
    private var tracked: Set<String> = []

    /// 지켜볼 Codex 스레드를 바꾼다. 비면 묻기를 멈춘다.
    func track(_ threadIds: Set<String>) {
        tracked = threadIds
        guard !threadIds.isEmpty else {
            stop()
            publish([:])
            return
        }
        publish(statuses.filter { threadIds.contains($0.key) })
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !inFlight else { return }
        guard let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: orcaBundleIdentifier)
            .first?.bundleURL else {
            publish([:])
            return
        }
        inFlight = true
        queue.async { [weak self] in
            let result = Self.fetch(appURL: appURL)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                // 못 읽었으면 지난 값을 들고 있지 않는다. 승인이 끝났는데 파란색이 남는 것보다 롤아웃 상태로 돌아가는 편이 낫다.
                self.publish((result ?? [:]).filter { self.tracked.contains($0.key) })
            }
        }
    }

    private func publish(_ next: [String: OrcaChatStatus]) {
        guard next != statuses else { return }
        statuses = next
        onChange?()
    }

    private static func fetch(appURL: URL) -> [String: OrcaChatStatus]? {
        let clientPath = appURL.appendingPathComponent("Contents/Resources/app.asar.unpacked/out/cli/runtime-client.js").path
        guard FileManager.default.fileExists(atPath: clientPath) else { return nil }
        let userDataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/orca").path
        guard let json = try? JSONSerialization.data(withJSONObject: ["clientPath": clientPath, "userDataPath": userDataPath]),
              let encoded = String(data: json, encoding: .utf8),
              let output = runOrcaProcess(appURL.appendingPathComponent("Contents/MacOS/Orca"), ["-e", orcaChatStatusScript],
                                          extraEnvironment: ["ELECTRON_RUN_AS_NODE": "1", "RETTO_ORCA_REQUEST": encoded],
                                          timeout: 5) else { return nil }
        return orcaChatStatuses(fromOutput: output)
    }
}
