import Foundation
@main struct LedgerTest {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  let a = try TraceFoxBackupLedger(root:root.appendingPathComponent("a"))
  let b = try TraceFoxBackupLedger(root:root.appendingPathComponent("b"))
  let original = TraceFoxArchiveRecord(peer:42,namespace:0,message:1,timestamp:100,text:"first",deleted:false,files:["one.media.jpg"])
  let unsent = try a.contains(original);precondition(!unsent)
  try a.acknowledge(original)
  let reopened = try TraceFoxBackupLedger(root:root.appendingPathComponent("a"))
  let saved = try reopened.contains(original);let foreign = try b.contains(original)
  precondition(saved && !foreign)
  let edit = TraceFoxArchiveRecord(peer:42,namespace:0,message:1,timestamp:100,text:"changed",deleted:false,files:original.files)
  let deletion = TraceFoxArchiveRecord(peer:42,namespace:0,message:1,timestamp:100,text:original.text,deleted:true,files:original.files)
  let media = TraceFoxArchiveRecord(peer:42,namespace:0,message:1,timestamp:100,text:original.text,deleted:false,files:["two.media.jpg"])
  for changed in [edit,deletion,media] { let found = try reopened.contains(changed);precondition(!found) }
  try Data("broken".utf8).write(to:root.appendingPathComponent("a/sent.json"))
  do { _ = try TraceFoxBackupLedger(root:root.appendingPathComponent("a"));fatalError("Corrupt ledger silently reset") } catch {}
  print("PASS: durable backup acknowledgement, edit/delete/media retry identity, account roots and corruption handling")
 }
}
