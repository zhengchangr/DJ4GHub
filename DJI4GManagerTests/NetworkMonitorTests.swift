import XCTest
@testable import DJI4GManager

final class NetworkMonitorTests: XCTestCase {

    func testParseIfconfig() {
        let sample = """
        lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
        \tinet 127.0.0.1 netmask 0xff000000
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tinet 192.168.1.5 netmask 0xffffff00 broadcast 192.168.1.255
        \tstatus: active
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tinet 192.168.225.3 netmask 0xffffff00 broadcast 192.168.225.255
        \tstatus: active
        utun0: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
        \tstatus: active
        """
        let interfaces = NetworkMonitor.interfaces(from: sample)
        XCTAssertEqual(interfaces.count, 2)
        XCTAssertEqual(interfaces.first { $0.name == "en5" }?.ipv4, "192.168.225.3")
        XCTAssertEqual(interfaces.first { $0.name == "en5" }?.status, "active")
    }

    func testParseNetstat() {
        let sample = """
        Name  Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0   16384 <Link#1>                        12345     0  1000000 12345     0  2000000     0
        en5   1500  <Link#8>    c2:58:42:e2:67:bc    99999     0  50000000 88888     0  30000000     0
        """
        let counters = NetworkMonitor.counters(from: sample)
        XCTAssertEqual(counters["en5"]?.rx, 50_000_000)
        XCTAssertEqual(counters["en5"]?.tx, 30_000_000)
    }

    func testParseDefaultRoute() {
        let sample = """
           route to: default
        destination: default
           gateway: 192.168.225.1
         interface: en5
        """
        let route = NetworkMonitor.defaultRoute(from: sample)
        XCTAssertEqual(route.iface, "en5")
        XCTAssertEqual(route.gateway, "192.168.225.1")
    }

    func testParseNetworkServiceOrder() {
        let sample = """
        An asterisk (*) denotes that a network service is disabled.

        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) Baiwang
        (Hardware Port: Baiwang, Device: en5)

        (3) *USB LAN
        (Hardware Port: USB LAN, Device: en7)
        """
        let services = NetworkMonitor.services(from: sample)
        XCTAssertEqual(services.count, 3)
        XCTAssertEqual(services[0].name, "Wi-Fi")
        XCTAssertEqual(services[0].device, "en0")
        XCTAssertEqual(services[1].name, "Baiwang")
        XCTAssertEqual(services[1].port, "Baiwang")
        XCTAssertEqual(services[1].device, "en5")
        XCTAssertEqual(services[2].name, "USB LAN")
        XCTAssertEqual(services[2].device, "en7")
    }
}
