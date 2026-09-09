import XCTest
@testable import DJ4GHub

final class SMSCodecTests: XCTestCase {

    func testGSM7RoundTrip() {
        let text = "Hello, world! 12345"
        let septets = SMSCodec.gsm7Encode(text)
        XCTAssertNotNil(septets)
        let packed = SMSCodec.packSeptets(septets!)
        let unpacked = SMSCodec.unpackSeptets(packed, count: septets!.count)
        XCTAssertEqual(SMSCodec.decodeSeptets(unpacked), text)
    }

    func testGSM7AlphabetUsesStandardIndexes() {
        // 标准 GSM 7-bit 默认字母表：@=0、空格=32、A=65、a=97、t=116
        XCTAssertEqual(SMSCodec.gsm7Encode("@"), [0])
        XCTAssertEqual(SMSCodec.gsm7Encode(" "), [32])
        XCTAssertEqual(SMSCodec.gsm7Encode("A"), [65])
        XCTAssertEqual(SMSCodec.gsm7Encode("a"), [97])
        XCTAssertEqual(SMSCodec.gsm7Encode("test"), [116, 101, 115, 116])
        XCTAssertEqual(SMSCodec.decodeSeptets([116, 101, 115, 116]), "test")
    }

    func testGSM7ExtensionCharacters() {
        let text = "Price: 10 EUR [ok]"
        let septets = SMSCodec.gsm7Encode(text)
        XCTAssertNotNil(septets)
        let packed = SMSCodec.packSeptets(septets!)
        let unpacked = SMSCodec.unpackSeptets(packed, count: septets!.count)
        XCTAssertEqual(SMSCodec.decodeSeptets(unpacked), text)
    }

    func testUCS2FallbackForChinese() {
        XCTAssertNil(SMSCodec.gsm7Encode("你好，世界"))
    }

    func testDeliverPDURoundTripGSM7() {
        let sender = "+8613800138000"
        let text = "Hello from DJI module"
        let pdu = SMSCodec.buildDeliverPDU(sender: sender, text: text)
        let hex = SMSCodec.bytesToHex(pdu)
        let message = SMSCodec.parseDeliverPDU(hex: hex, id: 1, isRead: true)
        XCTAssertEqual(message?.phoneNumber, sender)
        XCTAssertEqual(message?.text, text)
    }

    func testDeliverPDURoundTripUCS2() {
        let sender = "10086"
        let text = "验证码：123456"
        let pdu = SMSCodec.buildDeliverPDU(sender: sender, text: text)
        let hex = SMSCodec.bytesToHex(pdu)
        let message = SMSCodec.parseDeliverPDU(hex: hex, id: 1, isRead: true)
        XCTAssertEqual(message?.phoneNumber, sender)
        XCTAssertEqual(message?.text, text)
    }

    func testSubmitPDUBuildsValidLength() throws {
        let pdu = try SMSCodec.buildSubmitPDU(to: "+8613800138000", text: "Test")
        // lengthOctets 应等于 PDU 数据长度减 1（不含短信中心长度字节）
        XCTAssertEqual(pdu.lengthOctets, pdu.data.count - 1)
        XCTAssertEqual(pdu.data.first, 0x00)
    }

    func testEncodeAddressUsesDigitCount() {
        // 3GPP 23.040：地址长度按“数字个数”计，而不是字节数
        XCTAssertEqual(SMSCodec.encodeAddress("+8613800138000").length, 13)
        XCTAssertEqual(SMSCodec.encodeAddress("10086").length, 5)
    }

    func testSubmitPDUAddressLengthIsDigitCount() throws {
        let pdu = try SMSCodec.buildSubmitPDU(to: "+8613800138000", text: "Test")
        // PDU 布局：SMSC 长度(0x00) / 首字节(0x01) / 消息参考号(0x00) / 地址长度
        XCTAssertEqual(pdu.data[3], 13)
    }

    func testParseRealDeviceDeliverPDU() {
        // 真机模块返回的 SMS-DELIVER PDU：
        // 地址长度是数字个数（04 = 4 位号码 2020），SCTS 半字节对调存储。
        let hex = "079144872000302320048102020000625061028204401AD9775D0E72D7DBE2B21C949E8360B75A4E7683D16AB71B"
        let message = SMSCodec.parseDeliverPDU(hex: hex, id: 7, isRead: false)
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.phoneNumber, "2020")
        XCTAssertFalse(message?.text.isEmpty ?? true)
        XCTAssertNotNil(message?.date)
    }

    func testParseCMGLRealCRLFFormat() {
        let hex = "079144872000302320048102020000625061028204401AD9775D0E72D7DBE2B21C949E8360B75A4E7683D16AB71B"
        // 真机响应使用 \r\n 行尾，且 status 1=已读、0=未读
        let response = "+CMGL: 7,1,,38\r\n\(hex)\r\n+CMGL: 8,0,,38\r\n\(hex)\r\nOK\r\n"
        let messages = SMSCodec.parseCMGL(response)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].id, 7)
        XCTAssertTrue(messages[0].isRead)
        XCTAssertEqual(messages[1].id, 8)
        XCTAssertFalse(messages[1].isRead)
    }

    func testSCTSRoundTrip() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 16,
            hour: 20, minute: 28, second: 4
        ))!
        let scts = SMSCodec.encodeSCTS(date)
        let decoded = SMSCodec.decodeSCTS(scts)
        XCTAssertEqual(decoded?.timeIntervalSince1970, date.timeIntervalSince1970)
    }

    func testParseCMGLFromDemoTransport() throws {
        let transport = DemoTransport()
        try transport.open()
        let response = try transport.command("AT+CMGL=4", timeout: 3)
        let messages = SMSCodec.parseCMGL(response)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].phoneNumber, "+8613800138000")
        XCTAssertFalse(messages[0].text.isEmpty)
        XCTAssertEqual(messages[1].phoneNumber, "10086")
    }

    func testICCIDEncodingDecoding() {
        let iccid = "89860095020312345678"
        let bytes = ESIMProtocol.TLV.encodeICCID(iccid)
        XCTAssertEqual(bytes.count, 10)
        XCTAssertEqual(ESIMProtocol.TLV.decodeICCID(bytes), iccid)
    }
}
