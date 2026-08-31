// 레토를 걷어내는 실제 작업. 발바닥 메뉴와 `--uninstall` 이 같은 코드를 쓴다.
//
// 앱 설정과 앱 본체는 여기서 건드리지 않는다. 지우는 순서가 화면이 있느냐에 따라 달라서다 —
// 창이 있으면 AppKit 이 종료할 때 프레임을 설정에 도로 쓰므로 설정 삭제가 맨 끝이어야 한다.

import AppKit
import Foundation
import ServiceManagement

struct UninstallOutcome {
    var lines: [String] = []
    var hadProblem = false

    mutating func ok(_ line: String) { lines.append("· " + line) }
    mutating func warn(_ line: String) {
        lines.append("· ⚠ " + line)
        hadProblem = true
    }
}

/// 훅 등록·상태 파일·자동 실행을 걷어낸다.
func performUninstall(bundle: Bundle = .main) -> UninstallOutcome {
    var outcome = UninstallOutcome()
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser

    // 1. 훅 등록. 앱을 지운 뒤에는 번들 안의 설치기를 쓸 수 없으니 이걸 먼저 한다.
    if let script = bundle.url(forResource: "install", withExtension: "cjs", subdirectory: "hook"),
       let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
           .first(where: { fileManager.isExecutableFile(atPath: $0) }) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [script.path, "--uninstall"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { outcome.ok("Claude·Codex 훅 등록을 뺐습니다") }
            else { outcome.warn("훅 등록을 빼지 못했습니다 — Claude settings.json과 Codex hooks.json을 확인해 주세요") }
        } catch {
            outcome.warn("훅 제거를 실행하지 못했습니다 — Claude settings.json과 Codex hooks.json을 확인해 주세요")
        }
    } else {
        outcome.warn("node 가 없어 훅 등록이 남습니다 — Claude settings.json과 Codex hooks.json을 확인해 주세요")
    }

    // 2. 상태 파일과 설치된 훅. 옛 이름(reto-pet)으로 깔렸던 폴더도 같이 본다.
    var removedState = false
    for name in [".claude/retto-pet", ".claude/reto-pet"] {
        let directory = home.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: directory.path) else { continue }
        do {
            try fileManager.removeItem(at: directory)
            removedState = true
        } catch {
            outcome.warn("상태 파일을 지우지 못했습니다 (~/\(name))")
        }
    }
    if removedState { outcome.ok("상태 파일을 지웠습니다") }

    // 3. 자동 실행. 남겨 두면 지워진 앱을 계속 띄우려 한다.
    if SMAppService.mainApp.status == .enabled {
        do {
            try SMAppService.mainApp.unregister()
            outcome.ok("자동 실행을 껐습니다")
        } catch {
            outcome.warn("자동 실행을 끄지 못했습니다 — 시스템 설정 → 로그인 항목에서 빼 주세요")
        }
    }

    return outcome
}
