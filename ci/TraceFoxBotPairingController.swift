import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI
import SGConfig

private enum AutomaticConnectionSection: Int32, SGItemListSection { case connection }
private typealias AutomaticConnectionEntry = SGItemListUIEntry<AutomaticConnectionSection, Int, Int, Int, Int, Int>
public func traceFoxBotPairingController(context: AccountContext) -> ViewController {
    let message = Promise<String>()
    let explanation = "Підключення та резервне копіювання запускаються автоматично після входу. Окремо вмикати їх не потрібно. Секретні чати зберігаються локально."
    message.set(.single(explanation))
    let store = TraceFoxBotCredentialStore(accountRecordId: context.account.id.int64)
    let owner = context.account.peerId.id._internalGetInt64Value()
    var task: TraceFoxBotClaimTask?
    var client: TraceFoxBotLinkClient?
    var closed = false
    DispatchQueue(label: "tracefox.connection.status").async {
        do {
            if let credentials = try store.read(ownerId: owner), let origin = URL(string: SG_CONFIG.apiUrl) {
                let connection = try TraceFoxBotLinkClient(origin: origin)
                DispatchQueue.main.async {
                    guard !closed else { return }
                    client = connection
                    do {
                        task = try connection.status(credentials: credentials) { result in
                            DispatchQueue.main.async {
                                guard !closed else { return }
                                let status: String
                                switch result {
                                case let .success(value): status = value.archive_available ? "Підключено. Сервер підтвердив доступ до резервних копій." : "Підключено. Сервер ще не підтвердив Premium-доступ TraceFox."
                                case .failure: status = "Стан сервера поки не підтверджено. Застосунок повторить підключення автоматично."
                                }
                                message.set(.single(status + "\n\n" + explanation))
                            }
                        }
                    } catch { message.set(.single(explanation)) }
                }
            }
        } catch { message.set(.single("Захищене сховище поки недоступне. " + explanation)) }
    }
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { _ in })
    let signal = combineLatest(context.sharedContext.presentationData, message.get()) |> deliverOnMainQueue
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [AutomaticConnectionEntry] = [.notice(id: 0, section: .connection, text: text)]
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Підключення TraceFox"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (state, (list, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in closed = true; task?.cancel(); task = nil; client = nil }
    return controller
}
