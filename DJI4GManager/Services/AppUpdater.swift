import CryptoKit
import Foundation

/// 从 GitHub Releases 检查、下载并安装新版 DJI 4G Manager。
enum AppUpdater {
    static let repo = "zhengchangr/dji-4g-manager"
    static let assetName = "DJI4GManager-Release.zip"

    /// 当前安装版本的短版本号（CFBundleShortVersionString）。
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - 数据模型

    struct GitHubRelease: Decodable {
        let tagName: String
        let name: String
        let body: String?
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, prerelease, assets
        }
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    struct UpdateInfo: Identifiable {
        let tagName: String
        let name: String
        let notes: String?
        let assetName: String
        let assetURL: URL
        let assetDigest: String?

        var id: String { tagName }
    }

    // MARK: - 检查更新

    /// 拉取 GitHub 上的 Release 列表（接口按发布时间从新到旧返回）。
    static func fetchReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: URL(
            string: "https://api.github.com/repos/\(repo)/releases?per_page=30"
        )!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DJI4GManager/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModemError.commandFailed("无法连接 GitHub 检查更新，请稍后重试。")
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    /// 从 Release 列表里挑出值得提示的更新：版本号比当前新，且带 macOS 安装包。
    static func pickUpdate(from releases: [GitHubRelease], currentVersion: String = AppUpdater.currentVersion) -> UpdateInfo? {
        let current = numericVersion(currentVersion) ?? []
        for release in releases {
            guard let updateVersion = numericVersion(release.tagName),
                  isNewer(updateVersion, than: current) else { continue }
            guard let asset = release.assets.first(where: { $0.name == assetName }) else { continue }
            return UpdateInfo(
                tagName: release.tagName,
                name: release.name,
                notes: release.body,
                assetName: asset.name,
                assetURL: asset.browserDownloadURL,
                assetDigest: asset.digest
            )
        }
        return nil
    }

    private static func isNewer(_ lhs: [Int], than rhs: [Int]) -> Bool {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// 把 "v0.2.1-beta.1" 这类标签解析成主版本号 [0, 2, 1]。
    static func numericVersion(_ tag: String) -> [Int]? {
        let base = tag
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? tag
        let parts = base.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    // MARK: - 下载与安装

    /// 下载安装包到应用支持目录并解压，返回解压后的 .app 路径。
    static func prepareUpdate(_ update: UpdateInfo) async throws -> URL {
        let fileManager = FileManager.default
        let updatesRoot = try applicationSupportDirectory()
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent(update.tagName, isDirectory: true)
        try fileManager.createDirectory(at: updatesRoot, withIntermediateDirectories: true)

        let zipURL = updatesRoot.appendingPathComponent(assetName)
        let (temporaryURL, response) = try await URLSession.shared.download(from: update.assetURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModemError.commandFailed("下载安装包失败，请稍后重试。")
        }
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: zipURL)

        if let expectedDigest = update.assetDigest, !expectedDigest.isEmpty {
            let actualDigest = sha256Hex(of: zipURL)
            let expectedHex = expectedDigest.replacingOccurrences(of: "sha256:", with: "")
            guard actualDigest.lowercased() == expectedHex.lowercased() else {
                throw ModemError.commandFailed("安装包校验失败，已停止更新以保证安全。")
            }
        }

        let appURL = updatesRoot.appendingPathComponent("DJI4GManager.app", isDirectory: true)
        if fileManager.fileExists(atPath: appURL.path) {
            try fileManager.removeItem(at: appURL)
        }
        try runDitto(arguments: ["-x", "-k", zipURL.path, updatesRoot.path])
        guard fileManager.fileExists(atPath: appURL.path) else {
            throw ModemError.commandFailed("解压安装包失败，未找到 DJI4GManager.app。")
        }
        return appURL
    }

    /// 安排安装：退出旧程序后由后台脚本替换并重新打开新版。
    static func scheduleInstall(stagedApp: URL) throws {
        let currentApp = Bundle.main.bundleURL
        let stagingRoot = stagedApp.deletingLastPathComponent()
        let script = """
        sleep 2
        rm -rf \(shellQuote(currentApp.path))
        ditto \(shellQuote(stagedApp.path)) \(shellQuote(currentApp.path))
        rm -rf \(shellQuote(stagingRoot.path))
        open \(shellQuote(currentApp.path))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/sh", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: - 工具

    private static func applicationSupportDirectory() throws -> URL {
        let url = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DJI4GManager", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModemError.commandFailed("解压安装包失败（ditto 退出码 \(process.terminationStatus)）。")
        }
    }

    private static func sha256Hex(of url: URL) -> String {
        guard let stream = InputStream(url: url) else { return "" }
        stream.open()
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let chunkSize = buffer.count
        while stream.hasBytesAvailable {
            let read = buffer.withUnsafeMutableBytes {
                stream.read($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: chunkSize)
            }
            guard read > 0 else { break }
            hasher.update(data: Data(buffer[0..<read]))
        }
        stream.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
