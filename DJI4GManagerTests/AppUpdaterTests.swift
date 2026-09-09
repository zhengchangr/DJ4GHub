import XCTest
@testable import DJI4GManager

final class AppUpdaterTests: XCTestCase {

    private func releasesJSON(_ body: String) -> Data {
        Data("""
        [
          \(body)
        ]
        """.utf8)
    }

    func testNumericVersionParsesTagAndPrerelease() {
        XCTAssertEqual(AppUpdater.numericVersion("v0.3.0-beta.1"), [0, 3, 0])
        XCTAssertEqual(AppUpdater.numericVersion("0.2.0"), [0, 2, 0])
        XCTAssertEqual(AppUpdater.numericVersion("v1.0.0"), [1, 0, 0])
        XCTAssertNil(AppUpdater.numericVersion("latest"))
    }

    func testPickUpdateSkipsSameVersion() throws {
        let data = releasesJSON("""
        {
          "tag_name": "v0.2.0-beta.1",
          "name": "DJI 4G Manager 0.2.0 测试版",
          "body": "test",
          "prerelease": true,
          "assets": [{
            "name": "DJI4GManager-Release.zip",
            "browser_download_url": "https://example.com/DJI4GManager-Release.zip",
            "digest": "sha256:abcd"
          }]
        }
        """)
        let releases = try JSONDecoder().decode([AppUpdater.GitHubRelease].self, from: data)
        XCTAssertNil(AppUpdater.pickUpdate(from: releases, currentVersion: "0.2.0"))
        XCTAssertNotNil(AppUpdater.pickUpdate(from: releases, currentVersion: "0.1.0"))
    }

    func testPickUpdatePrefersNewerAndRequiresAsset() throws {
        let data = releasesJSON("""
        {
          "tag_name": "v0.3.1-beta.2",
          "name": "DJI 4G Manager 0.3.1 测试版",
          "body": null,
          "prerelease": true,
          "assets": [{
            "name": "wrong-name.zip",
            "browser_download_url": "https://example.com/wrong.zip",
            "digest": null
          }]
        },
        {
          "tag_name": "v0.3.0",
          "name": "DJI 4G Manager 0.3.0",
          "body": "release",
          "prerelease": false,
          "assets": [{
            "name": "DJI4GManager-Release.zip",
            "browser_download_url": "https://example.com/DJI4GManager-Release.zip",
            "digest": "sha256:1234"
          }]
        }
        """)
        let releases = try JSONDecoder().decode([AppUpdater.GitHubRelease].self, from: data)
        let picked = AppUpdater.pickUpdate(from: releases, currentVersion: "0.2.0")
        XCTAssertNotNil(picked)
        XCTAssertEqual(picked?.tagName, "v0.3.0")
        XCTAssertEqual(picked?.name, "DJI 4G Manager 0.3.0")
    }
}
