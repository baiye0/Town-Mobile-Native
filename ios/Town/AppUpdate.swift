import Foundation
import Combine

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let body: String?
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, body }
}

@MainActor final class AppUpdateStore: ObservableObject {
    enum Phase { case idle, checking, current, available, unavailable }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published var message = "尚未检查更新"
    private let repository = "baiye0/Town-Mobile-Native"

    func check() async {
        phase = .checking; message = "正在检查更新…"
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Being-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease else { throw URLError(.cannotParseResponse) }
            let version = release.tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            guard version.split(separator: ".").count == 3 else { throw URLError(.cannotParseResponse) }
            latestVersion = version; releaseURL = release.htmlURL
            if Self.compare(version, currentVersion) > 0 { phase = .available; message = "发现新版本 \(version)。请通过 TestFlight 或发布页安装。" }
            else { phase = .current; message = "当前已是最新正式版本（\(currentVersion)）" }
        } catch { phase = .unavailable; message = "暂时无法检查更新，可以稍后重试或打开发布页。" }
    }

    static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 { if (x[safe: i] ?? 0) != (y[safe: i] ?? 0) { return (x[safe: i] ?? 0) < (y[safe: i] ?? 0) ? -1 : 1 } }
        return 0
    }
}

private extension Array { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }
