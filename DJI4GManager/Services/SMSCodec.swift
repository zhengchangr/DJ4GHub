import Foundation

/// GSM 短信 PDU 编解码（提交 / 接收）。
enum SMSCodec {

    // MARK: - GSM 7-bit 默认字母表

    private static let alphabet: [Character] = Array(
        "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\u{1B}ÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
    )

    private static let extensionTable: [Character: UInt8] = [
        "\n": 0x0A, "^": 0x14, "{": 0x28, "}": 0x29, "\\": 0x2F,
        "[": 0x3C, "~": 0x3D, "]": 0x3E, "|": 0x40, "€": 0x65,
    ]

    private static var alphabetIndex: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (index, char) in alphabet.enumerated() {
            map[char] = UInt8(index)
        }
        return map
    }()

    // MARK: - 编码

    /// 尝试用 GSM 7-bit 默认字母表编码，无法编码的字符返回 nil。
    static func gsm7Encode(_ text: String) -> [UInt8]? {
        var septets: [UInt8] = []
        for char in text {
            if let index = alphabetIndex[char] {
                septets.append(index)
            } else if let ext = extensionTable[char] {
                septets.append(0x1B)
                septets.append(ext)
            } else {
                return nil
            }
        }
        return septets
    }

    static func packSeptets(_ septets: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var bitBuffer: UInt32 = 0
        var bitCount = 0
        for septet in septets {
            bitBuffer |= UInt32(septet) << bitCount
            bitCount += 7
            while bitCount >= 8 {
                out.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitCount -= 8
            }
        }
        if bitCount > 0 {
            out.append(UInt8(bitBuffer & 0xFF))
        }
        return out
    }

    /// 构造 SMS-SUBMIT PDU。
    static func buildSubmitPDU(to phoneNumber: String, text: String) throws -> (data: [UInt8], lengthOctets: Int) {
        var pdu: [UInt8] = []
        pdu.append(0x00) // 使用 SIM 卡默认短信中心
        pdu.append(0x01) // 首字节：MTI=SMS-SUBMIT，无有效期
        pdu.append(0x00) // 消息参考号

        let (addressLength, address) = encodeAddress(phoneNumber)
        pdu.append(addressLength)
        pdu.append(contentsOf: address)
        pdu.append(0x00) // PID

        if let septets = gsm7Encode(text) {
            guard septets.count <= 160 else {
                throw ModemError.commandFailed("短信过长（GSM 7-bit 最多 160 个字符），请分段发送")
            }
            pdu.append(0x00) // DCS：GSM 7-bit
            pdu.append(UInt8(septets.count)) // UDL 以 septet 计数
            pdu.append(contentsOf: packSeptets(septets))
        } else {
            let ucs2 = Array(text.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
            guard ucs2.count <= 140 else {
                throw ModemError.commandFailed("短信过长（UCS2 最多 70 个字符），请分段发送")
            }
            pdu.append(0x08) // DCS：UCS2
            pdu.append(UInt8(ucs2.count)) // UDL 以字节计数
            pdu.append(contentsOf: ucs2)
        }

        let lengthOctets = pdu.count - 1 // 不含短信中心长度字节
        return (pdu, lengthOctets)
    }

    /// 构造 SMS-DELIVER PDU（演示与测试用）。
    static func buildDeliverPDU(sender: String, text: String, date: Date = Date()) -> [UInt8] {
        var pdu: [UInt8] = [0x00] // 短信中心长度
        pdu.append(0x00) // 首字节：MTI=SMS-DELIVER

        let (addressLength, address) = encodeAddress(sender)
        pdu.append(addressLength)
        pdu.append(contentsOf: address)
        pdu.append(0x00) // PID

        if let septets = gsm7Encode(text) {
            pdu.append(0x00)
            pdu.append(contentsOf: encodeSCTS(date))
            pdu.append(UInt8(septets.count))
            pdu.append(contentsOf: packSeptets(septets))
        } else {
            let ucs2 = Array(text.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
            pdu.append(0x08)
            pdu.append(contentsOf: encodeSCTS(date))
            pdu.append(UInt8(ucs2.count))
            pdu.append(contentsOf: ucs2)
        }
        return pdu
    }

    // MARK: - 解码

    static func unpackSeptets(_ bytes: [UInt8], count: Int, startBit: Int = 0) -> [UInt8] {
        var out: [UInt8] = []
        var bitBuffer: UInt64 = 0
        var bitCount = 0
        var index = 0
        var remainingSkip = max(startBit, 0)
        while out.count < count {
            // 带分段头时，正文可能从某个非整字节的位偏移开始，先把偏移位吞掉。
            while bitCount < remainingSkip + 7, index < bytes.count {
                bitBuffer |= UInt64(bytes[index]) << bitCount
                bitCount += 8
                index += 1
            }
            if remainingSkip > 0 {
                bitBuffer >>= remainingSkip
                bitCount -= remainingSkip
                remainingSkip = 0
            }
            guard bitCount >= 7 else { break }
            out.append(UInt8(bitBuffer & 0x7F))
            bitBuffer >>= 7
            bitCount -= 7
        }
        return out
    }

    static func decodeSeptets(_ septets: [UInt8]) -> String {
        var result = ""
        var index = 0
        while index < septets.count {
            let value = septets[index]
            if value == 0x1B {
                if index + 1 < septets.count {
                    let ext = septets[index + 1]
                    let chars: [UInt8: Character] = [
                        0x0A: "\n", 0x14: "^", 0x28: "{", 0x29: "}",
                        0x2F: "\\", 0x3C: "[", 0x3D: "~", 0x3E: "]",
                        0x40: "|", 0x65: "€",
                    ]
                    result.append(chars[ext] ?? "?")
                    index += 2
                    continue
                }
                break
            }
            if Int(value) < alphabet.count {
                result.append(alphabet[Int(value)])
            }
            index += 1
        }
        return result
    }

    /// 解析 `AT+CMGL` 返回的多条短信。
    static func parseCMGL(_ response: String) -> [SMSMessage] {
        var messages: [SMSMessage] = []
        let lines = response.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("+CMGL:") {
                let header = line.replacingOccurrences(of: "+CMGL:", with: "")
                let parts = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2, let messageID = Int(parts[0]) {
                    let status = Int(parts[1]) ?? 1
                    var pduHex = ""
                    var j = index + 1
                    while j < lines.count {
                        let candidate = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !candidate.isEmpty {
                            pduHex = candidate
                            break
                        }
                        j += 1
                    }
                    if let message = parseDeliverPDU(hex: pduHex, id: messageID, isRead: status == 1) {
                        messages.append(message)
                    }
                    index = j + 1
                    continue
                }
            }
            index += 1
        }
        return messages
    }

    static func parseDeliverPDU(hex: String, id: Int, isRead: Bool) -> SMSMessage? {
        let bytes = hexToBytes(hex)
        guard bytes.count > 2 else { return nil }
        let smscLength = Int(bytes[0])
        var pos = 1 + smscLength
        guard pos < bytes.count else { return nil }

        let firstOctet = bytes[pos]
        pos += 1
        guard firstOctet & 0x03 == 0x00 else { return nil } // 仅处理 SMS-DELIVER

        // 地址长度按 3GPP 23.040 是“数字个数”（半字节数），
        // 地址区实际字节数为 1（TOA）+ ceil(位数/2)（BCD 半字节）。
        let addressLength = Int(bytes[pos])
        pos += 1
        var sender = ""
        if addressLength > 0 {
            let addressOctets = 1 + (addressLength + 1) / 2
            guard pos + addressOctets <= bytes.count else { return nil }
            let addressBytes = Array(bytes[pos ..< pos + addressOctets])
            sender = decodeAddress(addressBytes)
            pos += addressOctets
        }
        guard pos + 9 <= bytes.count else { return nil }

        pos += 1 // PID
        let dcs = bytes[pos]
        pos += 1
        let date = decodeSCTS(Array(bytes[pos ..< pos + 7]))
        pos += 7
        let udl = Int(bytes[pos])
        pos += 1
        let hasUDH = (firstOctet & 0x40) != 0
        let coding = dcs & 0x0C
        let udByteCount = coding == 0x08 ? udl : (udl * 7 + 7) / 8
        let udEnd = min(pos + max(udByteCount, 0), bytes.count)
        let ud = pos < udEnd ? Array(bytes[pos ..< udEnd]) : []
        let text = decodeUserData(ud, dcs: dcs, udl: udl, hasUDH: hasUDH)
        let concat = hasUDH ? parseConcatInfo(from: ud) : nil
        return SMSMessage(
            id: id,
            phoneNumber: sender,
            text: text,
            date: date,
            isRead: isRead,
            isIncoming: true,
            concat: concat,
            rawHex: bytesToHex(bytes)
        )
    }

    // MARK: - 地址与时间

    static func encodeAddress(_ phone: String) -> (length: UInt8, bytes: [UInt8]) {
        let normalized = phone.replacingOccurrences(of: "+", with: "")
        let digits = Array(normalized)
        var packed: [UInt8] = []
        var index = 0
        while index < digits.count {
            let first = digits[index]
            let second = index + 1 < digits.count ? digits[index + 1] : "F"
            packed.append((hexValue(second) << 4) | hexValue(first))
            index += 2
        }
        let tonNPI: UInt8 = phone.hasPrefix("+") ? 0x91 : 0x81
        // 地址长度 = 数字个数（半字节数），不含 TOA 字节
        return (UInt8(digits.count), [tonNPI] + packed)
    }

    static func decodeAddress(_ bytes: [UInt8]) -> String {
        guard let tonNPI = bytes.first else { return "" }
        var digits = ""
        for byte in bytes.dropFirst() {
            let first = byte & 0x0F
            let second = byte >> 4
            if first < 10 { digits.append(Character(String(first))) }
            if second < 10 { digits.append(Character(String(second))) }
        }
        if tonNPI == 0x91 { return "+" + digits }
        return digits
    }

    static func decodeSCTS(_ bytes: [UInt8]) -> Date? {
        guard bytes.count == 7 else { return nil }
        func twoDigits(_ value: UInt8) -> Int {
            // SCTS 每个两位数字都是半字节对调存储（如 "26" -> 0x62）
            Int((value & 0x0F) * 10 + ((value >> 4) & 0x0F))
        }
        let year = 2000 + twoDigits(bytes[0])
        let month = twoDigits(bytes[1])
        let day = twoDigits(bytes[2])
        let hour = twoDigits(bytes[3])
        let minute = twoDigits(bytes[4])
        let second = twoDigits(bytes[5])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let local = calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )) else {
            return nil
        }
        // 第 7 字节为时区：以 15 分钟为单位，bit7 为符号（1=西区）
        let tz = bytes[6]
        let quarterHours = Int(tz & 0x0F) * 10 + Int((tz >> 4) & 0x07)
        let negative = (tz & 0x80) != 0
        let offsetSeconds = (negative ? -quarterHours : quarterHours) * 15 * 60
        // SCTS 是短信中心当地时间，转 UTC 需减去时区偏移
        return local.addingTimeInterval(-TimeInterval(offsetSeconds))
    }

    /// 把时间编码成 SMS-DELIVER 的 SCTS 7 字节（YYMMDDHHMMSS + 时区，半字节反转）。
    static func encodeSCTS(_ date: Date) -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func swapDigits(_ value: Int) -> UInt8 {
            let tens = UInt8((value % 100) / 10)
            let ones = UInt8(value % 10)
            return (ones << 4) | tens
        }
        return [
            swapDigits((components.year ?? 2026) % 100),
            swapDigits(components.month ?? 1),
            swapDigits(components.day ?? 1),
            swapDigits(components.hour ?? 0),
            swapDigits(components.minute ?? 0),
            swapDigits(components.second ?? 0),
            0x00, // 时区：0 个 15 分钟
        ]
    }

    /// 解析用户数据头（UDH）中的“长短信分片”信息。
    /// 支持 8 位引用号（IEI 0x00）与 16 位引用号（IEI 0x08）两种格式。
    static func parseConcatInfo(from ud: [UInt8]) -> SMSConcatInfo? {
        guard let udhl = ud.first else { return nil }
        let headerEnd = min(1 + Int(udhl), ud.count)
        guard headerEnd >= 2 else { return nil }
        var offset = 1
        while offset + 1 < headerEnd {
            let iei = ud[offset]
            let length = Int(ud[offset + 1])
            let dataStart = offset + 2
            let dataEnd = dataStart + length
            guard dataEnd <= headerEnd else { break }
            let data = Array(ud[dataStart ..< dataEnd])
            if iei == 0x00, length >= 3,
               data[1] >= 1, data[2] >= 1, data[2] <= data[1] {
                return SMSConcatInfo(
                    reference: Int(data[0]),
                    totalParts: Int(data[1]),
                    partIndex: Int(data[2])
                )
            }
            if iei == 0x08, length >= 4,
               data[2] >= 1, data[3] >= 1, data[3] <= data[2] {
                return SMSConcatInfo(
                    reference: Int(data[0]) << 8 | Int(data[1]),
                    totalParts: Int(data[2]),
                    partIndex: Int(data[3])
                )
            }
            offset = dataEnd
        }
        return nil
    }

    static func decodeUserData(_ bytes: [UInt8], dcs: UInt8, udl: Int, hasUDH: Bool = false) -> String {
        let coding = dcs & 0x0C
        // 有分段头时，用户数据第一个字节是 UDHL，头部共占 UDHL+1 个字节。
        let headerOctets = hasUDH ? (bytes.first.map { Int($0) + 1 } ?? 0) : 0
        let bodyStart = min(headerOctets, bytes.count)
        if coding == 0x08 {
            // UCS2
            var utf16 = [UInt16]()
            var index = bodyStart
            while index + 1 < bytes.count {
                utf16.append(UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
                index += 2
            }
            return String(decoding: utf16, as: UTF16.self)
        } else if coding == 0x00 {
            // GSM 7-bit 默认字母表
            var bodySeptets = udl
            var startBit = 0
            if headerOctets > 0 {
                // 头部按字节数占用，但 7-bit 数据按 septet 计数；
                // 头部之后还要补 0–6 位，使正文从下一个 septet 边界开始。
                let headerSeptets = (headerOctets * 8 + 6) / 7
                startBit = headerSeptets * 7 - headerOctets * 8
                bodySeptets = max(udl - headerSeptets, 0)
            }
            // 先跳过头部整字节，再处理头尾的 0–6 个补位。
            let bodyBytes = Array(bytes.dropFirst(headerOctets))
            let septets = unpackSeptets(bodyBytes, count: bodySeptets, startBit: startBit)
            return decodeSeptets(septets)
        } else {
            // 8-bit 数据，尽量按 Latin-1 展示
            return String(bytes: bytes[bodyStart...], encoding: .isoLatin1) ?? ""
        }
    }

    // MARK: - 工具

    static func hexToBytes(_ hex: String) -> [UInt8] {
        let clean = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            if let value = UInt8(clean[index ..< next], radix: 16) {
                bytes.append(value)
            }
            index = next
        }
        return bytes
    }

    static func bytesToHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func hexValue(_ char: Character) -> UInt8 {
        guard let value = UInt8(String(char), radix: 16) else { return 0x0F }
        return value
    }
}
