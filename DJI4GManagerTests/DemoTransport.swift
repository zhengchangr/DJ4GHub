import Foundation
@testable import DJI4GManager

/// 测试用模拟通道：返回一组固定的真实格式响应，用于测试 AT 解析逻辑。
final class DemoTransport: ModemTransport {
    private var openFlag = false
    private var usbNetMode = 0

    var isOpen: Bool { openFlag }

    func open() throws {
        openFlag = true
    }

    func close() {
        openFlag = false
    }

    func command(_ command: String, timeout: TimeInterval) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch trimmed {
        case "AT":
            return "OK"
        case "AT+CGMI":
            return "+CGMI: Baiwang\r\nOK"
        case "AT+CGMM":
            return "+CGMM: QDC507\r\nOK"
        case "AT+CGMR":
            return "+CGMR: QDC507GLEFM21\r\nOK"
        case "AT+CGSN":
            return "861234567890123\r\nOK"
        case "AT+CPIN?":
            return "+CPIN: READY\r\nOK"
        case "AT+CSQ":
            return "+CSQ: 24,0\r\nOK"
        case "AT+COPS?":
            return "+COPS: 0,0,\"CHN-UNICOM\",7\r\nOK"
        case "AT+QNWINFO":
            return "+QNWINFO: \"FDD LTE\",\"460 01\",\"LTE BAND 3\",1650\r\nOK"
        case "AT+QCFG=\"USBNET\"":
            return "+QCFG: \"usbnet\",\(usbNetMode)\r\nOK"
        case "AT+QCFG=\"USBCFG\"":
            return "+QCFG: \"usbcfg\",0x2CA3,0x4006,1,1,1,1,1,0,0\r\nOK"
        case "AT+CGPADDR=1":
            return "+CGPADDR: 1,192.168.225.1\r\nOK"
        case "AT+CNUM":
            return "+CNUM: \"\",\"+8613800138000\",145\r\nOK"
        case "AT+CGDCONT?":
            return "+CGDCONT: 1,\"IP\",\"wonet\",\"0.0.0.0\",0,0\r\nOK"
        case "AT+CGACT?":
            return "+CGACT: 1,1\r\nOK"
        case "AT+CMGF=0":
            return "OK"
        case "AT+CMGL=4":
            return demoCMGLResponse
        case "AT+CFUN=1,1":
            return "OK"
        default:
            if trimmed.hasPrefix("AT+QCFG=\"USBNET\","), let value = trimmed.last, let mode = Int(String(value)) {
                usbNetMode = mode
                return "OK"
            }
            if trimmed.hasPrefix("AT+CCHO=") {
                return "+CCHO: 4\r\nOK"
            }
            if trimmed.hasPrefix("AT+CGLA=") {
                let response = demoAPDUResponse(for: command)
                return "+CGLA: \(response.count / 2),\(SMSCodec.bytesToHex(response))\r\nOK"
            }
            if trimmed.hasPrefix("AT+CMGD=") {
                return "OK"
            }
            return "OK"
        }
    }

    func commandWithPrompt(_ command: String, followUp: [UInt8], timeout: TimeInterval) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("AT+CMGS=") {
            return "+CMGS: 1\r\nOK"
        }
        return "OK"
    }

    /// 根据请求 APDU 返回对应的测试响应（数据 + SW 9000）。
    private func demoAPDUResponse(for command: String) -> [UInt8] {
        let parts = command.uppercased().split(separator: "\"")
        guard parts.count >= 2 else { return [0x90, 0x00] }
        // APDU 前 5 字节是 CLA/INS/P1/P2/Lc 头，TLV 从请求体开始
        let request = Array(SMSCodec.hexToBytes(String(parts[1])).dropFirst(5))

        func hasTag(_ tag: UInt16) -> Bool {
            var index = 0
            while index < request.count {
                var current: UInt16
                if request[index] == 0x9F || request[index] == 0xBF {
                    guard index + 1 < request.count else { return false }
                    current = UInt16(request[index]) << 8 | UInt16(request[index + 1])
                    index += 2
                } else {
                    current = UInt16(request[index])
                    index += 1
                }
                if current == tag { return true }
                guard index < request.count else { return false }
                var length = Int(request[index])
                index += 1
                if length & 0x80 != 0 {
                    let count = length & 0x7F
                    guard index + count <= request.count else { return false }
                    length = 0
                    for _ in 0 ..< count {
                        length = length << 8 | Int(request[index])
                        index += 1
                    }
                }
                index += length
            }
            return false
        }

        var data: [UInt8] = []
        if hasTag(0xBF3E) {
            let eid = "89049032123456789012345678901234"
            let nibbles = SMSCodec.hexToBytes(eid)
            data = ESIMProtocol.TLV.encode(tag: 0xBF3E, content: ESIMProtocol.TLV.encode(tag: 0x5A, content: nibbles))
        } else if hasTag(0xBF2D) {
            let first = demoProfileTLV(iccid: "89860095020312345678", nickname: "中国联通", provider: "China Unicom", state: 1)
            let second = demoProfileTLV(iccid: "89860113911122334455", nickname: "中国移动", provider: "China Mobile", state: 0)
            data = ESIMProtocol.TLV.encode(tag: 0xBF2D, content: ESIMProtocol.TLV.encode(tag: 0xA0, content: first + second))
        } else if let op = [0xBF31, 0xBF32, 0xBF33, 0xBF29].first(where: { hasTag($0) }) {
            data = ESIMProtocol.TLV.encode(tag: op, content: [0x80, 0x01, 0x00])
        } else {
            data = []
        }
        return data + [0x90, 0x00]
    }

    private func demoProfileTLV(iccid: String, nickname: String, provider: String, state: UInt8) -> [UInt8] {
        var content = ESIMProtocol.TLV.encode(tag: 0x5A, content: ESIMProtocol.TLV.encodeICCID(iccid))
        content += ESIMProtocol.TLV.encode(tag: 0x90, content: Array(nickname.utf8))
        content += ESIMProtocol.TLV.encode(tag: 0x91, content: Array(provider.utf8))
        content += ESIMProtocol.TLV.encode(tag: 0x9F70, content: [state])
        return ESIMProtocol.TLV.encode(tag: 0xE3, content: content)
    }

    private var demoCMGLResponse: String {
        let first = SMSCodec.buildDeliverPDU(sender: "+8613800138000", text: "您好，这是演示短信。", date: Date())
        let second = SMSCodec.buildDeliverPDU(sender: "10086", text: "您的验证码是 123456。", date: Date().addingTimeInterval(-3600))
        let firstHex = SMSCodec.bytesToHex(first)
        let secondHex = SMSCodec.bytesToHex(second)
        return """
        +CMGL: 1,1,,\(firstHex.count / 2)
        \(firstHex)
        +CMGL: 2,1,,\(secondHex.count / 2)
        \(secondHex)
        OK
        """
    }
}
