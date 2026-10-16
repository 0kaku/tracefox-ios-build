import Foundation

public struct TraceFoxUpdateInfo {
    public let build: Int64
    public let page: URL
    public static func parse(_ data: Data, installedBuild: Int64) throws -> TraceFoxUpdateInfo? {
        guard data.count <= 512 * 1024, installedBuild >= 0,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["draft"] as? Bool == false, value["prerelease"] as? Bool == false,
              let tag = value["tag_name"] as? String, tag.hasPrefix("ios-build-"),
              !tag.dropFirst(10).isEmpty, tag.dropFirst(10).utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let build = Int64(tag.dropFirst(10)), build > 0,
              let pageText = value["html_url"] as? String, let page = URL(string: pageText),
              page.scheme == "https", page.host == "github.com", page.user == nil, page.password == nil,
              page.path == "/0kaku/tracefox-ios-build/releases/tag/" + tag,
              page.query == nil, page.fragment == nil,
              let assets = value["assets"] as? [[String: Any]],
              assets.contains(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }) else {
            throw NSError(domain: "TraceFoxUpdates", code: 1)
        }
        return build > installedBuild ? TraceFoxUpdateInfo(build: build, page: page) : nil
    }
}
