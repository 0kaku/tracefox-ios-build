import Postbox

let viewOnceTimeout: Int32 = Int32.max
final class AutoremoveTimeoutMessageAttribute {
    let timeout: Int32
    init(_ timeout: Int32) { self.timeout = timeout }
}
final class AutoclearTimeoutMessageAttribute {
    let timeout: Int32
    init(_ timeout: Int32) { self.timeout = timeout }
}
struct FixtureResource: MediaResource { let fixtureKey: String }
struct FixtureDimensions { let width: Int32; let height: Int32 }
struct FixtureImageRepresentation {
    let dimensions: FixtureDimensions
    let resource: MediaResource
}
final class TelegramMediaImage: Media {
    let representations: [FixtureImageRepresentation]
    init(_ representations: [FixtureImageRepresentation]) { self.representations = representations }
}
final class TelegramMediaFile: Media {
    let resource: MediaResource
    let fileName: String?
    let mimeType: String
    init(resource: MediaResource, fileName: String?, mimeType: String) {
        self.resource = resource; self.fileName = fileName; self.mimeType = mimeType
    }
}
