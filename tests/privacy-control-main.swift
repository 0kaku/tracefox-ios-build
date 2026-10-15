import Foundation
import SwiftSignalKit

@main struct PrivacyControlTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let network = Network(basePath: root.appendingPathComponent("account").path)
        let enable = TraceFoxPrivacyControl.setEnabled(true, network: network)
        precondition(network.requests == 0)
        let initial = try TraceFoxPrivacyRuntime.preferences(network: network).readEnabled()
        precondition(!initial)
        var completed = false
        _ = enable.start(error: { _ in fatalError("Unexpected failure") }, completed: { completed = true })
        precondition(completed && network.requests == 1 && network.wasEnabledBeforeRequest)
        network.failRequest = true
        var offlineFailure = false
        _ = TraceFoxPrivacyControl.setEnabled(true, network: network).start(error: {
            if case .offlineUpdateFailed = $0 { offlineFailure = true }
        })
        let stillEnabled = try TraceFoxPrivacyRuntime.preferences(network: network).readEnabled()
        precondition(offlineFailure && stillEnabled)
        let requestsBeforeDisable = network.requests
        _ = TraceFoxPrivacyControl.setEnabled(false, network: network).start()
        let disabled = try TraceFoxPrivacyRuntime.preferences(network: network).readEnabled()
        precondition(!disabled && network.requests == requestsBeforeDisable)
        let badRoot = root.appendingPathComponent("blocked")
        try Data("file, not account directory".utf8).write(to: badRoot)
        let badNetwork = Network(basePath: badRoot.path)
        var writeFailure = false
        _ = TraceFoxPrivacyControl.setEnabled(true, network: badNetwork).start(error: {
            if case .settingsWriteFailed = $0 { writeFailure = true }
        })
        precondition(writeFailure && badNetwork.requests == 0)
        print("PASS: real privacy control ordering, lazy execution, network failure persistence, disable and write failure; synchronous API fixtures only")
    }
}
