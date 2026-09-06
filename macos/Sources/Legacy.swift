// 옛 이름으로 깔린 레토를 정리한다.
//
// 이름이 두 번 바뀌었다 — `Reto Claude Pet.app` → `Retto Claude Pet.app` → `Retto.app`.
// `build.sh --install` 은 옛 이름을 걷어내지만, dmg 는 그냥 끌어다 놓는 것이라 그 장치가 없다.
// 그대로 두면 두 마리가 뜨고, 같은 `sessions.json` 을 읽으니 똑같은 말을 두 번 한다.
//
// **옛 앱의 「레토 제거」를 부르지 않는다.** 그쪽 제거기는 `~/.claude/retto-pet` 을 통째로
// 지우는데 우리 `hook.sh` 가 거기 있다. 게다가 그쪽은 훅을 `args` 배열로만 찾아서
// 지금 형식(`command` 한 줄)을 자기 것으로 알아보지 못한다 — 등록은 남고 파일만 사라져
// 레토가 다시 쳐다만 보는 상태가 된다. 그래서 번들만 휴지통으로 옮긴다.

import AppKit

let legacyAppNames = ["Retto Claude Pet.app", "Reto Claude Pet.app"]
let legacyBundleIdentifiers = ["com.luxia.retto-claude-pet", "com.luxia.reto-claude-pet"]

/// 옛 이름 앱이 깔릴 수 있는 자리. dmg 로 끌어다 놓으면 `/Applications`,
/// 직접 빌드해 깔면 `~/Applications` 다.
func legacyAppURLs(manager: FileManager = .default) -> [URL] {
    let roots = [
        URL(fileURLWithPath: "/Applications"),
        manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]
    var found: [URL] = []
    for root in roots {
        for name in legacyAppNames {
            let candidate = root.appendingPathComponent(name)
            if manager.fileExists(atPath: candidate.path) { found.append(candidate) }
        }
    }
    return found
}

/// 옛 앱을 내리고 휴지통으로 옮긴다. 옮긴 것의 이름을 돌려준다.
///
/// 지우지 않고 휴지통으로 보내는 이유는, 남의 기기에서 앱을 없애는 일이라
/// 되돌릴 길을 남겨야 하기 때문이다.
func removeLegacyApps() -> [String] {
    var moved: [String] = []
    for identifier in legacyBundleIdentifiers {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
            app.terminate()
        }
    }

    for url in legacyAppURLs() {
        let done = DispatchSemaphore(value: 0)
        var failed: Error?
        NSWorkspace.shared.recycle([url]) { _, error in
            failed = error
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        if failed == nil { moved.append(url.lastPathComponent) }
    }
    return moved
}
