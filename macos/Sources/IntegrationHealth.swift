import Foundation

enum IntegrationConnectionState {
    case disabled, connecting, connected, reconnecting, failed

    func notice(service: String) -> String? {
        switch self {
        case .disabled, .connected: return nil
        case .connecting: return "\(service) 연결 중"
        case .reconnecting: return "\(service) 재연결 중 · 새 메시지 지연 가능"
        case .failed: return "\(service) 연결 확인 필요"
        }
    }
}

/// 말풍선은 현재 작업에 영향을 주는 문제만 표시한다. 전체 연결 진단은 메뉴에서 확인한다.
func taskConnectionNotice(for payload: StatePayload?, unreadablePaths: Set<String>, slackNotice: String?) -> String? {
    guard let payload, !payload.isClosed else { return nil }
    if payload.source == "slack" { return slackNotice }
    guard payload.source == "codex" || payload.client == "codex",
          [.running, .review, .waiting].contains(payload.petState),
          let path = payload.transcriptPath, unreadablePaths.contains(path) else { return nil }
    return "현재 작업의 상태를 확인할 수 없어요 · 연결 메뉴를 확인해 주세요"
}
