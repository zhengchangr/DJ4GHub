import Foundation

/// eUICC SGP.22 协议层：通过逻辑通道（AT+CCHO / AT+CGLA）执行 ES10 命令。
/// 命令帧格式参考 lpac：CLA=0x80、INS=0xE2（STORE DATA）、P1=0x91、P2=序号，
/// 请求体为 SGP.22 TLV。
enum ESIMProtocol {

    // MARK: - APDU 执行

    static func execute(transport: any ModemTransport, channel: UInt8, request: [UInt8]) throws -> [UInt8] {
        var apdu: [UInt8] = [0x80, 0xE2, 0x91, 0x00]
        apdu.append(UInt8(request.count))
        apdu.append(contentsOf: request)

        var collected: [UInt8] = []
        while true {
            let response = try ATClient.transmitAPDU(transport: transport, channel: channel, apdu: apdu)
            guard response.count >= 2 else {
                throw ModemError.commandFailed("APDU 响应过短")
            }
            let sw1 = response[response.count - 2]
            let sw2 = response[response.count - 1]
            collected.append(contentsOf: response.dropLast(2))

            if sw1 == 0x61 {
                // 还有更多数据，使用 GET RESPONSE 继续读取
                apdu = [0x00, 0xC0, 0x00, 0x00, sw2]
                continue
            }
            if (sw1 & 0xF0) == 0x90 {
                return collected
            }
            throw ModemError.commandFailed(String(format: "APDU 返回错误 SW=%02X%02X", sw1, sw2))
        }
    }

    // MARK: - ES10c 命令

    /// 读取 EID（GetEuiccData：请求 BF3E + tagList 5A）。
    static func getEID(transport: any ModemTransport, channel: UInt8) throws -> String {
        let request = TLV.encode(tag: 0xBF3E, content: TLV.encode(tag: 0x5C, content: [0x5A]))
        let response = try execute(transport: transport, channel: channel, request: request)
        guard let outer = TLV.parse(response).first(where: { $0.tag == 0xBF3E }),
              let tlv = TLV.parse(outer.content).first(where: { $0.tag == 0x5A }) else {
            throw ModemError.commandFailed("GetEID 响应缺少 5A 字段")
        }
        let raw = tlv.content
        if let direct = String(data: Data(raw), encoding: .utf8),
           direct.filter(\.isNumber).count >= 30 {
            return direct
        }
        let hex = raw.map { String(format: "%02X", $0) }.joined()
        return hex.filter(\.isNumber).count >= 30 ? hex : hex
    }

    /// 读取已安装 Profile 列表（GetProfilesInfo）。
    static func getProfilesInfo(transport: any ModemTransport, channel: UInt8) throws -> [ESIMProfile] {
        let request = TLV.encode(tag: 0xBF2D, content: [])
        let response = try execute(transport: transport, channel: channel, request: request)
        guard let outer = TLV.parse(response).first(where: { $0.tag == 0xBF2D }) else {
            throw ModemError.commandFailed("GetProfilesInfo 响应缺少 BF2D 字段")
        }
        guard let container = TLV.parse(outer.content).first(where: { $0.tag == 0xA0 }) else {
            return []
        }

        var profiles: [ESIMProfile] = []
        for entry in TLV.parse(container.content) where entry.tag == 0xE3 {
            var iccid = ""
            var name = ""
            var provider: String?
            var state = "disabled"
            for child in TLV.parse(entry.content) {
                switch child.tag {
                case 0x5A:
                    iccid = TLV.decodeICCID(child.content)
                case 0x90:
                    name = String(decoding: child.content, as: UTF8.self)
                case 0x91:
                    provider = String(decoding: child.content, as: UTF8.self)
                case 0x92 where name.isEmpty:
                    name = String(decoding: child.content, as: UTF8.self)
                case 0x9F70:
                    state = child.content.first == 1 ? "enabled" : "disabled"
                default:
                    break
                }
            }
            if !iccid.isEmpty {
                profiles.append(ESIMProfile(
                    iccid: iccid,
                    name: name,
                    state: state,
                    serviceProvider: provider,
                    isDefault: state == "enabled"
                ))
            }
        }
        return profiles
    }

    static func enableProfile(transport: any ModemTransport, channel: UInt8, iccid: String) throws {
        try runProfileCommand(transport: transport, channel: channel, opTag: 0xBF31, iccid: iccid, withRefreshFlag: true)
    }

    static func disableProfile(transport: any ModemTransport, channel: UInt8, iccid: String) throws {
        try runProfileCommand(transport: transport, channel: channel, opTag: 0xBF32, iccid: iccid, withRefreshFlag: true)
    }

    static func deleteProfile(transport: any ModemTransport, channel: UInt8, iccid: String) throws {
        try runProfileCommand(transport: transport, channel: channel, opTag: 0xBF33, iccid: iccid, withRefreshFlag: false)
    }

    static func setNickname(transport: any ModemTransport, channel: UInt8, iccid: String, nickname: String) throws {
        let content = TLV.encode(tag: 0x5A, content: TLV.encodeICCID(iccid))
            + TLV.encode(tag: 0x90, content: Array(nickname.utf8))
        let request = TLV.encode(tag: 0xBF29, content: content)
        try checkResult(transport: transport, channel: channel, request: request, opTag: 0xBF29)
    }

    private static func runProfileCommand(
        transport: any ModemTransport,
        channel: UInt8,
        opTag: UInt16,
        iccid: String,
        withRefreshFlag: Bool
    ) throws {
        var content = TLV.encode(tag: 0x5A, content: TLV.encodeICCID(iccid))
        if withRefreshFlag {
            content += TLV.encode(tag: 0x81, content: [0x00])
            let wrapped = TLV.encode(tag: 0xA0, content: content)
            try checkResult(transport: transport, channel: channel, request: TLV.encode(tag: opTag, content: wrapped), opTag: opTag)
        } else {
            try checkResult(transport: transport, channel: channel, request: TLV.encode(tag: opTag, content: content), opTag: opTag)
        }
    }

    private static func checkResult(
        transport: any ModemTransport,
        channel: UInt8,
        request: [UInt8],
        opTag: UInt16
    ) throws {
        let response = try execute(transport: transport, channel: channel, request: request)
        guard let outer = TLV.parse(response).first(where: { $0.tag == opTag }),
              let result = TLV.parse(outer.content).first(where: { $0.tag == 0x80 }),
              result.content.first == 0 else {
            throw ModemError.commandFailed("eUICC 操作未成功")
        }
    }

    // MARK: - TLV 工具

    enum TLV {
        static func encode(tag: UInt16, content: [UInt8]) -> [UInt8] {
            var out: [UInt8] = []
            if tag > 0xFF {
                out.append(UInt8(tag >> 8))
                out.append(UInt8(tag & 0xFF))
            } else {
                out.append(UInt8(tag))
            }
            out.append(contentsOf: encodeLength(content.count))
            out.append(contentsOf: content)
            return out
        }

        static func parse(_ data: [UInt8]) -> [(tag: UInt16, content: [UInt8])] {
            var result: [(tag: UInt16, content: [UInt8])] = []
            var index = 0
            while index < data.count {
                var tag: UInt16
                if data[index] == 0x9F || data[index] == 0xBF {
                    guard index + 1 < data.count else { break }
                    tag = UInt16(data[index]) << 8 | UInt16(data[index + 1])
                    index += 2
                } else {
                    tag = UInt16(data[index])
                    index += 1
                }
                guard index < data.count else { break }
                var length = Int(data[index])
                index += 1
                if length & 0x80 != 0 {
                    let count = length & 0x7F
                    guard index + count <= data.count else { break }
                    length = 0
                    for _ in 0 ..< count {
                        length = length << 8 | Int(data[index])
                        index += 1
                    }
                }
                guard index + length <= data.count else { break }
                result.append((tag, Array(data[index ..< index + length])))
                index += length
            }
            return result
        }

        /// 20 位 ICCID 数字 → GSM BCD 10 字节。
        static func encodeICCID(_ digits: String) -> [UInt8] {
            let chars = Array(digits.filter(\.isNumber))
            var out: [UInt8] = []
            var index = 0
            while index < chars.count {
                let first = hexValue(chars[index])
                let second = index + 1 < chars.count ? hexValue(chars[index + 1]) : 0x0F
                out.append((second << 4) | first)
                index += 2
            }
            return out
        }

        /// GSM BCD 字节 → ICCID 数字串。
        static func decodeICCID(_ bytes: [UInt8]) -> String {
            var digits = ""
            for byte in bytes {
                let low = byte & 0x0F
                let high = byte >> 4
                if low < 10 { digits.append(Character(String(low))) }
                if high < 10 { digits.append(Character(String(high))) }
            }
            return digits
        }

        private static func encodeLength(_ length: Int) -> [UInt8] {
            if length < 128 { return [UInt8(length)] }
            var bytes: [UInt8] = []
            var value = length
            while value > 0 {
                bytes.insert(UInt8(value & 0xFF), at: 0)
                value >>= 8
            }
            return [UInt8(0x80 | bytes.count)] + bytes
        }

        private static func hexValue(_ char: Character) -> UInt8 {
            guard let value = UInt8(String(char), radix: 16) else { return 0x0F }
            return value
        }
    }
}
