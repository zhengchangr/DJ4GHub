import Foundation
@testable import DJ4GHub

/// 测试用传输通道：按指令返回预设响应，未配置的指令一律返回 OK。
final class StaticTransport: ModemTransport {
    private var responses: [String: String]
    private var openFlag = false

    init(responses: [String: String]) {
        self.responses = responses
    }

    var isOpen: Bool { openFlag }

    func open() throws {
        openFlag = true
    }

    func close() {
        openFlag = false
    }

    func command(_ command: String, timeout: TimeInterval) throws -> String {
        let key = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return responses[key] ?? "OK"
    }

    func commandWithPrompt(_ command: String, followUp: [UInt8], timeout: TimeInterval) throws -> String {
        "OK"
    }
}
