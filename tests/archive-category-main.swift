import Foundation
import Postbox
@main struct CategoryTest {
 static func main() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let store = try TraceFoxArchiveStore(root: folder)
  func record(_ id: Int32, _ deleted: Bool, _ files: [String], _ ttl: Int32? = nil, _ peer: Int64 = 42) -> TraceFoxArchiveRecord {
   TraceFoxArchiveRecord(peer: peer, namespace: 0, message: id, timestamp: id, text: "fixture", deleted: deleted, files: files, ttlSeconds: ttl)
  }
  precondition(TraceFoxArchiveCategory.deletedMedia.includes(record(1,true,["saved.jpg"])))
  precondition(!TraceFoxArchiveCategory.deletedMedia.includes(record(1,true,[])))
  precondition(TraceFoxArchiveCategory.viewOnceMedia.includes(record(2,false,["saved.jpg"],Int32.max)))
  precondition(!TraceFoxArchiveCategory.viewOnceMedia.includes(record(2,false,["saved.jpg"],60)))
  precondition(!TraceFoxArchiveCategory.viewOnceMedia.includes(record(2,false,[],Int32.max)))
  precondition(TraceFoxArchiveCategory.secretChats.includes(record(3,false,[],nil,PeerId(9,namespace:3).toInt64())))
  precondition(!TraceFoxArchiveCategory.secretChats.includes(record(3,false,[],nil,PeerId(9,namespace:2).toInt64())))
  let source = folder.appendingPathComponent("source"); try Data("bytes".utf8).write(to:source)
  let file = try store.retain(source:source,peer:42,namespace:0,message:1,fileExtension:"jpg")
  for id: Int32 in 1...205 { try store.save(record(id,true,[file])) }
  for id: Int32 in 400...800 { try store.save(record(id,false,[])) }
  let match: (TraceFoxArchiveRecord)->Bool = { TraceFoxArchiveCategory.deletedMedia.includes($0) }
  let a = try store.records(matching:match)
  let b = try store.records(before:TraceFoxArchiveCursor(record:a.last!),matching:match)
  let d = try store.records(before:TraceFoxArchiveCursor(record:b.last!),matching:match)
  precondition(a.count == 100 && b.count == 100 && d.count == 5)
  precondition(Set((a+b+d).map{$0.message}).count == 205)
  print("PASS: actual iOS categories and filtered pagination; synthetic Postbox identity, no device emulation")
 }
}
