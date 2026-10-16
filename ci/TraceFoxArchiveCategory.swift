import Foundation
import Postbox

public enum TraceFoxArchiveCategory: Int, CaseIterable {
    case deletedMedia, viewOnceMedia, secretChats
    public var title: String {
        switch self {
        case .deletedMedia: return "Видалені медіа"
        case .viewOnceMedia: return "Одноразові медіа"
        case .secretChats: return "Секретні чати"
        }
    }
    public func includes(_ record: TraceFoxArchiveRecord) -> Bool {
        switch self {
        case .deletedMedia: return record.deleted && !record.files.isEmpty
        case .viewOnceMedia: return record.ttlSeconds == Int32.max && !record.files.isEmpty
        case .secretChats: return PeerId(record.peer).namespace._internalGetInt32Value() == 3
        }
    }
}
