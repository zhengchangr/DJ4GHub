import Foundation

enum ModemError: LocalizedError, Equatable {
    case deviceNotFound
    case notOpen
    case interfaceNotFound
    case timeout
    case commandFailed(String)
    case usb(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            "未找到大疆一代 4G 模块（USB 2ca3:4006），请确认已插入且线缆支持数据传输。"
        case .notOpen:
            "模块尚未打开。"
        case .interfaceNotFound:
            "没有找到可用的 USB AT 通信接口。"
        case .timeout:
            "AT 指令超时，没有收到模块响应。"
        case .commandFailed(let response):
            "模块返回错误：\(response)"
        case .usb(let detail):
            "USB 通信错误：\(detail)"
        }
    }
}

/// 模块传输通道抽象，方便接入真实硬件与演示模式。
protocol ModemTransport: AnyObject {
    var isOpen: Bool { get }
    func open() throws
    func close()
    func command(_ command: String, timeout: TimeInterval) throws -> String
    func commandWithPrompt(_ command: String, followUp: [UInt8], timeout: TimeInterval) throws -> String
}

/// 保证所有 USB / AT 操作都在同一条串行队列上执行，
/// 避免 libusb 上下文被多线程并发访问。
final class ModemSession {
    private let queue = DispatchQueue(label: "com.dji4gmanager.modem.session")
    private var transport: (any ModemTransport)?

    var isConnected: Bool {
        queue.sync { transport?.isOpen ?? false }
    }

    func connect(_ transport: any ModemTransport) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try transport.open()
                    self.transport = transport
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.transport?.close()
                self.transport = nil
                continuation.resume()
            }
        }
    }

    func run<T>(_ body: @escaping (any ModemTransport) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let transport = self.transport, transport.isOpen else {
                    continuation.resume(throwing: ModemError.notOpen)
                    return
                }
                do {
                    continuation.resume(returning: try body(transport))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
