import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI
import SGConfig

private struct BotPairingScreenState {
    var message = "Прив’язка дозволяє підтвердити власника акаунта. Синхронізацію повідомлень ще не підключено."
    var hasAttempt = false
    var busy = false
    var hasStoredToken = false
    var accountActive = true
}

private final class BotPairingScreenModel {
    let context: AccountContext
    let ownerId: Int64
    let store = TraceFoxBotCredentialStore()
    let state = Promise<BotPairingScreenState>()
    var current = BotPairingScreenState()
    var coordinator: TraceFoxBotPairingCoordinator?
    let accountObservation = MetaDisposable()
    var wasAccountVisible = false

    init(context: AccountContext) {
        self.context = context
        ownerId = context.account.peerId.id._internalGetInt64Value()
        do {
            guard let origin = URL(string: SG_CONFIG.apiUrl) else { throw TraceFoxBotLinkError.invalidOrigin }
            coordinator = TraceFoxBotPairingCoordinator(client: try TraceFoxBotLinkClient(origin: origin), store: store)
            current.hasStoredToken = try store.read(ownerId: ownerId) != nil
            if current.hasStoredToken { current.message = "Прив’язку збережено на пристрої. Її чинність на сервері ще не перевірено." }
        } catch { current.message = "Не вдалося підготувати прив’язку або відкрити захищене сховище." }
        state.set(.single(current))
        accountObservation.set((context.sharedContext.activeAccountsWithInfo
        |> deliverOnMainQueue).start(next: { [weak self] view in
            guard let self = self else { return }
            let present = view.accounts.contains(where: { $0.account.id == context.account.id })
            if present { self.wasAccountVisible = true }
            let active = present && view.primary == context.account.id
            if !active {
                self.cancel()
                self.current.message = "Акаунт більше не активний. Відкрийте прив’язку з налаштувань потрібного акаунта."
                if !present && self.wasAccountVisible {
                    try? self.store.remove(ownerId: self.ownerId)
                    self.current.hasStoredToken = false
                }
            }
            self.current.accountActive = active
            self.state.set(.single(self.current))
        }))
    }

    deinit { accountObservation.dispose(); coordinator?.cancel() }
    func cancel() {
        coordinator?.cancel()
        current.hasAttempt = false; current.busy = false
        state.set(.single(current))
    }

    func action(_ action: Int) {
        guard current.accountActive, !current.busy else { return }
        do {
            switch action {
            case 0:
                guard let coordinator = coordinator else { return }
                let command = try coordinator.begin(ownerId: ownerId)
                UIPasteboard.general.setItems([["public.utf8-plain-text": command]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
                current.hasAttempt = true
                current.message = "Код скопійовано на 10 хвилин. Вставте й надішліть його боту з цього акаунта, поверніться сюди та натисніть «Перевірити підтвердження»."
                context.sharedContext.applicationBindings.openUrl("https://t.me/" + SG_CONFIG.botUsername)
            case 1:
                guard let coordinator = coordinator, current.hasAttempt else { return }
                current.busy = true
                try coordinator.poll { [weak self] result in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.current.busy = false
                        switch result {
                        case .success(nil): self.current.message = "Підтвердження ще немає. Надішліть скопійований код боту з цього акаунта."
                        case .success(.some):
                            self.current.hasStoredToken = true; self.current.hasAttempt = false
                            self.current.message = "Акаунт підтверджено. Токен збережено в захищеному сховищі. Синхронізацію архіву ще не підключено."
                        case .failure: self.current.message = "Не вдалося підтвердити прив’язку. Перевірте мережу та строк дії коду."
                        }
                        self.state.set(.single(self.current))
                    }
                }
            case 2: cancel()
            case 3:
                cancel()
                try store.remove(ownerId: ownerId)
                current.hasStoredToken = false
                current.message = "Прив’язку видалено з цього пристрою."
            default: return
            }
        } catch { current.busy = false; current.message = "Операцію не завершено. Спробуйте створити новий код або повторити пізніше." }
        state.set(.single(current))
    }
}

private enum BotPairingSection: Int32, SGItemListSection { case pairing }
private typealias BotPairingEntry = SGItemListUIEntry<BotPairingSection, Int, Int, Int, Int, Int>

// Staged for compilation; settings navigation remains disabled until validation.
public func traceFoxBotPairingController(context: AccountContext) -> ViewController {
    let model = BotPairingScreenModel(context: context)
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { model.action($0) })
    let signal = combineLatest(context.sharedContext.presentationData, model.state.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [BotPairingEntry] = [.notice(id: 0, section: .pairing, text: state.message)]
        if state.accountActive && !state.busy {
            entries.append(.action(id: 1, section: .pairing, actionType: 0, text: "Скопіювати код і відкрити бота", kind: .generic))
            if state.hasAttempt {
                entries.append(.action(id: 2, section: .pairing, actionType: 1, text: "Перевірити підтвердження", kind: .generic))
                entries.append(.action(id: 3, section: .pairing, actionType: 2, text: "Скасувати спробу", kind: .generic))
            }
            if state.hasStoredToken { entries.append(.action(id: 4, section: .pairing, actionType: 3, text: "Видалити прив’язку з пристрою", kind: .generic)) }
        }
        let controller = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Бот TraceFox"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controller, (list, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { [weak model] _ in model?.cancel() }
    return controller
}
