import Foundation

struct CodexFrameRoute: Equatable {
    let method: String
    let conversationID: String
    let hostID: String
    let sourceClientID: String?
    let targetClientIDs: [String]?
    let version: Int?
    let revision: Int?
    let changeType: String?
    var messageType: String? = nil
}

/// 큰 JSON 본문은 저장하지 않고 라우팅 필드만 읽는다. 호출자는 프레임 전체를
/// consume한 뒤 route를 사용한다. 최대 깊이 128, 토큰 4096바이트, 대상 256개다.
struct CodexFrameMetadata {
    private enum Role { case root, params, change, targets, ignored }
    private enum State { case keyOrEnd, key, colon, objectValue, objectNext, valueOrEnd, arrayValue, arrayNext }
    private enum Field: String {
        case method, sourceClientId, targetClientIds, version, params
        case hostId, conversationId, change, revision, type
        case messageKind
    }
    private struct Container {
        let object: Bool
        let role: Role
        var state: State
        var key: Field?
        var seen: Set<Field> = []
    }
    private enum Destination { case key, field(Field), target, ignored }
    private enum Token { case none, string, number, literal }
    private enum NumberState { case minus, zero, integer, dot, fraction, exponent, exponentSign, exponentDigits }

    private var containers: [Container] = []
    private var token: Token = .none
    private var destination: Destination = .ignored
    private var bytes: [UInt8] = []
    private var keyTooLong = false
    private var escaped = false
    private var unicodeDigits = 0
    private var unicodeValue: UInt16 = 0
    private var highSurrogate = false
    private var lowSurrogateStage = 0
    private var utf8Remaining = 0
    private var utf8Lower: UInt8 = 0x80
    private var utf8Upper: UInt8 = 0xBF
    private var numberState: NumberState = .integer
    private var numberIsInteger = true
    private var literal: [UInt8] = []
    private var literalIndex = 0
    private var started = false
    private var completed = false
    private var invalid = false
    private var method: String?
    private var conversationID: String?
    private var hostID: String?
    private var sourceClientID: String?
    private var targetClientIDs: [String]?
    private var version: Int?
    private var revision: Int?
    private var changeType: String?
    private var messageType: String?
    private(set) var peakRetainedTokenBytes = 0

    var route: CodexFrameRoute? {
        guard completed, !invalid, case .none = token,
              let method, !method.isEmpty, let conversationID, !conversationID.isEmpty,
              let hostID, !hostID.isEmpty else { return nil }
        return CodexFrameRoute(method: method, conversationID: conversationID, hostID: hostID,
            sourceClientID: sourceClientID, targetClientIDs: targetClientIDs,
            version: version, revision: revision, changeType: changeType, messageType: messageType)
    }

    mutating func consume(_ data: Data) {
        guard !invalid else { return }
        for byte in data {
            consumeByte(byte)
            if invalid { break }
        }
    }

    private mutating func retain(_ byte: UInt8) {
        switch destination {
        case .ignored: return
        case .key:
            guard !keyTooLong else { return }
            if bytes.count >= 128 { keyTooLong = true; bytes.removeAll(keepingCapacity: true); return }
        case .field(.revision), .field(.type):
            // 버전별 본문 필드가 길거나 다른 형식이어도 안정적인 라우팅 정보는 남긴다.
            if bytes.count >= 4096 {
                destination = .ignored; bytes.removeAll(keepingCapacity: true); return
            }
        default:
            guard bytes.count < 4096 else { invalid = true; return }
        }
        bytes.append(byte)
        peakRetainedTokenBytes = max(peakRetainedTokenBytes, bytes.count)
    }

    private mutating func consumeByte(_ byte: UInt8) {
        guard !invalid else { return }
        switch token {
        case .string: consumeString(byte); return
        case .literal:
            guard literalIndex < literal.count, byte == literal[literalIndex] else { invalid = true; return }
            literalIndex += 1
            if literalIndex == literal.count { token = .none; finishValue() }
            return
        case .number:
            if consumeNumber(byte) { return }
            finishNumber()
            if invalid { return }
            consumeByte(byte)
            return
        case .none: break
        }
        if [UInt8(0x20), 0x09, 0x0A, 0x0D].contains(byte) { return }
        if completed { invalid = true; return }
        guard started else {
            guard byte == 0x7B else { invalid = true; return }
            started = true
            containers.append(Container(object: true, role: .root, state: .keyOrEnd))
            return
        }
        guard let current = containers.last else { invalid = true; return }
        switch current.state {
        case .keyOrEnd:
            if byte == 0x7D { closeContainer(object: true); return }
            fallthrough
        case .key:
            guard byte == 0x22 else { invalid = true; return }
            startString(current.role == .ignored ? .ignored : .key)
        case .colon:
            guard byte == 0x3A else { invalid = true; return }
            containers[containers.count - 1].state = .objectValue
        case .objectNext:
            if byte == 0x7D { closeContainer(object: true) }
            else if byte == 0x2C { containers[containers.count - 1].state = .key }
            else { invalid = true }
        case .arrayNext:
            if byte == 0x5D { closeContainer(object: false) }
            else if byte == 0x2C { containers[containers.count - 1].state = .arrayValue }
            else { invalid = true }
        case .valueOrEnd:
            if byte == 0x5D { closeContainer(object: false); return }
            fallthrough
        case .arrayValue, .objectValue: startValue(byte)
        }
    }

    private func valueDestination() -> Destination {
        guard let current = containers.last else { return .ignored }
        if current.role == .targets { return .target }
        guard let key = current.key else { return .ignored }
        return .field(key)
    }

    private mutating func startValue(_ byte: UInt8) {
        var dest = valueDestination()
        switch dest {
        case .field(.revision):
            if byte != 0x2D && !(0x30...0x39).contains(byte) { dest = .ignored }
        case .field(.type):
            if byte != 0x22 { dest = .ignored }
        case .field(.change):
            if byte != 0x7B { dest = .ignored }
        default: break
        }
        if byte == 0x7B || byte == 0x5B {
            let role: Role
            switch dest {
            case .field(.params): guard byte == 0x7B else { invalid = true; return }; role = .params
            case .field(.change): guard byte == 0x7B else { invalid = true; return }; role = .change
            case .field(.targetClientIds):
                guard byte == 0x5B else { invalid = true; return }
                role = .targets; targetClientIDs = []
            case .ignored: role = .ignored
            default: invalid = true; return
            }
            guard containers.count < 128 else { invalid = true; return }
            containers.append(Container(object: byte == 0x7B, role: role,
                state: byte == 0x7B ? .keyOrEnd : .valueOrEnd))
            return
        }
        if byte == 0x22 {
            switch dest {
            case .field(.version), .field(.revision), .field(.params), .field(.change), .field(.targetClientIds): invalid = true
            default: startString(dest)
            }
            return
        }
        if byte == 0x2D || (0x30...0x39).contains(byte) {
            switch dest {
            case .field(.version), .field(.revision), .ignored: break
            default: invalid = true; return
            }
            token = .number; destination = dest; bytes.removeAll(keepingCapacity: true)
            numberIsInteger = true
            numberState = byte == 0x2D ? .minus : byte == 0x30 ? .zero : .integer
            retain(byte)
            return
        }
        guard case .ignored = dest else { invalid = true; return }
        switch byte {
        case 0x74: literal = Array("true".utf8)
        case 0x66: literal = Array("false".utf8)
        case 0x6E: literal = Array("null".utf8)
        default: invalid = true; return
        }
        token = .literal; literalIndex = 1
    }

    private mutating func startString(_ dest: Destination) {
        token = .string; destination = dest; bytes.removeAll(keepingCapacity: true)
        keyTooLong = false; escaped = false; unicodeDigits = 0; unicodeValue = 0
        highSurrogate = false; lowSurrogateStage = 0; utf8Remaining = 0
        retain(0x22)
    }

    private mutating func consumeString(_ byte: UInt8) {
        retain(byte)
        guard !invalid else { return }
        if unicodeDigits > 0 {
            let digit: UInt16
            switch byte {
            case 0x30...0x39: digit = UInt16(byte - 0x30)
            case 0x41...0x46: digit = UInt16(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt16(byte - 0x61 + 10)
            default: invalid = true; return
            }
            unicodeValue = unicodeValue * 16 + digit; unicodeDigits -= 1
            if unicodeDigits == 0 {
                if highSurrogate {
                    guard (0xDC00...0xDFFF).contains(unicodeValue) else { invalid = true; return }
                    highSurrogate = false
                } else if (0xD800...0xDBFF).contains(unicodeValue) {
                    highSurrogate = true; lowSurrogateStage = 1
                } else if (0xDC00...0xDFFF).contains(unicodeValue) { invalid = true }
            }
            return
        }
        if lowSurrogateStage > 0 {
            if lowSurrogateStage == 1 {
                guard byte == 0x5C else { invalid = true; return }
                lowSurrogateStage = 2
            } else {
                guard byte == 0x75 else { invalid = true; return }
                lowSurrogateStage = 0; unicodeDigits = 4; unicodeValue = 0
            }
            return
        }
        if utf8Remaining > 0 {
            guard byte >= utf8Lower, byte <= utf8Upper else { invalid = true; return }
            utf8Remaining -= 1; utf8Lower = 0x80; utf8Upper = 0xBF
            return
        }
        if escaped {
            escaped = false
            if byte == 0x75 { unicodeDigits = 4; unicodeValue = 0 }
            else if ![UInt8(0x22), 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(byte) { invalid = true }
            return
        }
        if byte == 0x22 { finishString(); return }
        if byte == 0x5C { escaped = true; return }
        guard byte >= 0x20 else { invalid = true; return }
        if byte >= 0x80 {
            utf8Lower = 0x80; utf8Upper = 0xBF
            switch byte {
            case 0xC2...0xDF: utf8Remaining = 1
            case 0xE0: utf8Remaining = 2; utf8Lower = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF: utf8Remaining = 2
            case 0xED: utf8Remaining = 2; utf8Upper = 0x9F
            case 0xF0: utf8Remaining = 3; utf8Lower = 0x90
            case 0xF1...0xF3: utf8Remaining = 3
            case 0xF4: utf8Remaining = 3; utf8Upper = 0x8F
            default: invalid = true
            }
        }
    }

    private mutating func finishString() {
        token = .none
        let value: String?
        if case .ignored = destination { value = nil }
        else if keyTooLong { value = nil }
        else { value = try? JSONDecoder().decode(String.self, from: Data(bytes)) }
        switch destination {
        case .key:
            guard !containers.isEmpty else { invalid = true; return }
            let index = containers.count - 1
            let field = value.flatMap { recognizedField($0, role: containers[index].role) }
            if let field, !containers[index].seen.insert(field).inserted { invalid = true; return }
            containers[index].key = field; containers[index].state = .colon
        case .field(let field):
            guard let value else { invalid = true; return }
            switch field {
            case .method: method = value
            case .sourceClientId: sourceClientID = value
            case .hostId: hostID = value
            case .conversationId: conversationID = value
            case .type: changeType = value
            case .messageKind: messageType = value
            default: invalid = true; return
            }
            finishValue()
        case .target:
            guard let value, let count = targetClientIDs?.count, count < 256 else { invalid = true; return }
            targetClientIDs?.append(value); finishValue()
        case .ignored:
            if let current = containers.last, current.object, [.key, .keyOrEnd].contains(current.state) {
                containers[containers.count - 1].key = nil; containers[containers.count - 1].state = .colon
            } else { finishValue() }
        }
        bytes.removeAll(keepingCapacity: true)
    }

    private func recognizedField(_ name: String, role: Role) -> Field? {
        if role == .root, name == "type" { return .messageKind }
        guard let field = Field(rawValue: name) else { return nil }
        switch role {
        case .root: return [.method, .sourceClientId, .targetClientIds, .version, .params].contains(field) ? field : nil
        case .params: return [.hostId, .conversationId, .change].contains(field) ? field : nil
        case .change: return [.type, .revision].contains(field) ? field : nil
        default: return nil
        }
    }

    /// true이면 현재 숫자가 이 바이트까지 소비했다. false이면 구분자를 다시 처리한다.
    private mutating func consumeNumber(_ byte: UInt8) -> Bool {
        let digit = (0x30...0x39).contains(byte)
        switch numberState {
        case .minus:
            guard digit else { invalid = true; return true }
            numberState = byte == 0x30 ? .zero : .integer
        case .zero:
            if digit { invalid = true; return true }
            if byte == 0x2E { numberState = .dot; numberIsInteger = false }
            else if byte == 0x65 || byte == 0x45 { numberState = .exponent; numberIsInteger = false }
            else { return false }
        case .integer:
            if digit {} else if byte == 0x2E { numberState = .dot; numberIsInteger = false }
            else if byte == 0x65 || byte == 0x45 { numberState = .exponent; numberIsInteger = false }
            else { return false }
        case .dot:
            guard digit else { invalid = true; return true }; numberState = .fraction
        case .fraction:
            if digit {} else if byte == 0x65 || byte == 0x45 { numberState = .exponent; numberIsInteger = false }
            else { return false }
        case .exponent:
            if byte == 0x2B || byte == 0x2D { numberState = .exponentSign }
            else if digit { numberState = .exponentDigits }
            else { invalid = true; return true }
        case .exponentSign:
            guard digit else { invalid = true; return true }; numberState = .exponentDigits
        case .exponentDigits: if !digit { return false }
        }
        retain(byte)
        return true
    }

    private mutating func finishNumber() {
        guard [.zero, .integer, .fraction, .exponentDigits].contains(numberState) else { invalid = true; return }
        token = .none
        if case .field(let field) = destination {
            let value = numberIsInteger ? Int(String(decoding: bytes, as: UTF8.self)) : nil
            if field == .revision { revision = value }
            else if field == .version, let value { version = value }
            else { invalid = true; return }
        }
        bytes.removeAll(keepingCapacity: true)
        finishValue()
    }

    private mutating func finishValue() {
        guard !containers.isEmpty else { invalid = true; return }
        let index = containers.count - 1
        switch containers[index].state {
        case .objectValue: containers[index].state = .objectNext
        case .valueOrEnd, .arrayValue: containers[index].state = .arrayNext
        default: invalid = true
        }
    }

    private mutating func closeContainer(object: Bool) {
        guard containers.last?.object == object else { invalid = true; return }
        containers.removeLast()
        if containers.isEmpty { completed = true }
        else { finishValue() }
    }
}
