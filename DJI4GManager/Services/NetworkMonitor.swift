import Foundation
import Network

/// 读取 macOS 网络状态：网卡列表、默认路由与流量计数。
enum NetworkMonitor {
    private static var baselines: [String: ByteCounters] = [:]

    static func snapshot() -> NetworkSnapshot {
        let ifaces = interfaces()
        let route = defaultRoute()
        let counters = counters()
        var snap = NetworkSnapshot()
        snap.interfaces = ifaces
        snap.defaultRouteInterface = route.iface
        snap.defaultGateway = route.gateway
        snap.counters = counters

        // 大疆 4G 模块会以活动的以太网接口出现（常见名 Baiwang 或 enX，排除 en0）。
        let usbLike = ifaces.first {
            $0.status == "active" && $0.name.hasPrefix("en") && $0.name != "en0"
        }
        snap.activeInterface = usbLike?.name ?? ""
        snap.isAvailable = usbLike != nil
        snap.usingModuleAsDefault = usbLike != nil && route.iface == usbLike?.name

        if let name = usbLike?.name, let current = counters[name] {
            if let base = baselines[name], current.rx >= base.rx, current.tx >= base.tx {
                snap.sessionRX = current.rx - base.rx
                snap.sessionTX = current.tx - base.tx
            } else {
                baselines[name] = current
            }
        }
        return snap
    }

    static func interfaces() -> [MacInterfaceInfo] {
        guard let out = run("/sbin/ifconfig", []) else { return [] }
        return interfaces(from: out)
    }

    static func interfaces(from out: String) -> [MacInterfaceInfo] {
        var result: [MacInterfaceInfo] = []
        var current: MacInterfaceInfo?

        for rawLine in out.components(separatedBy: "\n") {
            let line = rawLine
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard var item = current else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("status:") {
                    item.status = trimmed.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("inet ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count > 1 { item.ipv4 = String(parts[1]) }
                }
                current = item
            } else if line.contains(":") {
                if let item = current, isRelevant(item.name) { result.append(item) }
                let name = line.split(separator: ":").first.map(String.init) ?? ""
                current = MacInterfaceInfo(name: name, status: "unknown", ipv4: "")
            }
        }
        if let item = current, isRelevant(item.name) { result.append(item) }
        return result
    }

    static func defaultRoute() -> (iface: String, gateway: String) {
        guard let out = run("/sbin/route", ["-n", "get", "default"]) else { return ("", "") }
        return defaultRoute(from: out)
    }

    static func defaultRoute(from out: String) -> (iface: String, gateway: String) {
        var iface = ""
        var gateway = ""
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                iface = trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("gateway:") {
                gateway = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (iface, gateway)
    }

    // MARK: - 网络服务顺序

    /// 读取系统网络服务列表（`networksetup -listnetworkserviceorder`）。
    static func services() -> [NetworkServiceInfo] {
        guard let out = run("/usr/sbin/networksetup", ["-listnetworkserviceorder"]) else { return [] }
        return services(from: out)
    }

    static func services(from out: String) -> [NetworkServiceInfo] {
        var result: [NetworkServiceInfo] = []
        var current: NetworkServiceInfo?
        for rawLine in out.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // 只认 "(1) Wi-Fi" 这种编号行，避免误把 Hardware Port 行当新服务
            if line.range(of: #"^\(\d+\)"#, options: .regularExpression) != nil,
               let close = line.firstIndex(of: ")") {
                if let item = current { result.append(item) }
                // "(1) Wi-Fi" / "(3) *USB LAN"
                let name = String(line[line.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^\\*+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                current = NetworkServiceInfo(name: name, port: "", device: "")
            } else if line.contains("Hardware Port:"), current != nil {
                let payload = line
                    .replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                let parts = payload.split(separator: ",", maxSplits: 1).map(String.init)
                current?.port = parts.first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if parts.count >= 2 {
                    current?.device = parts[1]
                        .replacingOccurrences(of: "Device:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if let item = current { result.append(item) }
        return result
    }

    /// 把指定网络服务排到第一位（需要管理员授权，会弹出系统密码框）。
    static func setDefaultService(_ name: String, allServices: [NetworkServiceInfo]) throws {
        var names = allServices.map { $0.name }
        names.removeAll { $0 == name }
        names.insert(name, at: 0)
        let quoted = names.map(shellQuote).joined(separator: " ")
        let script = "do shell script \"/usr/sbin/networksetup -ordernetworkservices \(quoted)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw ModemError.commandFailed("网络服务顺序调整失败（\(process.terminationStatus)）：\(detail)")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func counters() -> [String: ByteCounters] {
        guard let out = run("/usr/sbin/netstat", ["-ibn"]) else { return [:] }
        return counters(from: out)
    }

    static func counters(from out: String) -> [String: ByteCounters] {
        var result: [String: ByteCounters] = [:]
        for rawLine in out.components(separatedBy: "\n") {
            let fields = rawLine.split(separator: " ").map(String.init)
            if fields.count >= 10, fields[2].hasPrefix("<Link#") {
                let name = fields[0].replacingOccurrences(of: "*", with: "")
                if let rx = UInt64(fields[6]), let tx = UInt64(fields[9]) {
                    result[name] = ByteCounters(rx: rx, tx: tx)
                }
            }
        }
        return result
    }

    static func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func formattedSpeed(bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb >= 1024 { return String(format: "%.2f MB/s", kb / 1024) }
        return String(format: "%.1f KB/s", kb)
    }

    private static func isRelevant(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("lo") && !name.hasPrefix("utun") &&
            !name.hasPrefix("awdl") && !name.hasPrefix("llw") && !name.hasPrefix("ap")
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
