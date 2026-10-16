import Foundation
@main struct UpdateTest {
 static func main() throws {
  let release: [String: Any] = ["draft": false, "prerelease": false, "tag_name": "ios-build-20", "html_url": "https://github.com/0kaku/tracefox-ios-build/releases/tag/ios-build-20", "assets": [["name": "TraceFox.ipa"]]]
  let data = try JSONSerialization.data(withJSONObject: release)
  let newer = try TraceFoxUpdateInfo.parse(data, installedBuild: 19); precondition(newer?.build == 20)
  let same = try TraceFoxUpdateInfo.parse(data, installedBuild: 20); precondition(same == nil)
  for (key, value) in [("draft", true as Any), ("prerelease", true as Any), ("tag_name", "v1" as Any), ("html_url", "https://example.com/evil" as Any), ("assets", [] as Any)] {
   var bad = release; bad[key] = value
   do { _ = try TraceFoxUpdateInfo.parse(JSONSerialization.data(withJSONObject: bad), installedBuild: 1); fatalError("Invalid release accepted") } catch {}
  }
  print("PASS: update build comparison and release boundaries; no network or installation")
 }
}
