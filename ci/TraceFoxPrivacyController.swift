import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI

private struct PrivacyScreenState {
    var enabled: Bool
    var busy = false
    var message = ""
    var needsRetry = false
    var accountActive = false
}

private final class PrivacyScreenModel {
    let context: AccountContext
    let state = Promise<PrivacyScreenState>()
    var current: PrivacyScreenState
    let operation = MetaDisposable()
    let accountObservation = MetaDisposable()
    var generation: UInt64 = 0

    init(context: AccountContext) {
        self.context = context
        do {
            current = PrivacyScreenState(enabled: try TraceFoxPrivacyRuntime.preferences(network: context.account.network).readEnabled())
        } catch {
            current = PrivacyScreenState(enabled: true, message: "Не вдалося прочитати налаштування. Захист залишено увімкненим.")
        }
        state.set(.single(current))
        accountObservation.set((context.sharedContext.activeAccountsWithInfo
        |> deliverOnMainQueue).start(next: { [weak self] view in
            guard let self = self else { return }
            let active = view.primary == context.account.id && view.accounts.contains(where: { $0.account.id == context.account.id })
            guard active != self.current.accountActive else { return }
            self.generation &+= 1
            self.operation.set(nil)
            self.current.accountActive = active
            self.current.busy = false
            self.current.needsRetry = false
            if active {
                do {
                    self.current.enabled = try TraceFoxPrivacyRuntime.preferences(network: context.account.network).readEnabled()
                    self.current.message = ""
                } catch {
                    self.current.enabled = true
                    self.current.message = "Не вдалося прочитати налаштування. Захист залишено увімкненим."
                }
            } else {
                self.current.message = "Акаунт більше не активний. Відкрийте приватність із налаштувань потрібного акаунта."
            }
            self.state.set(.single(self.current))
        }))
    }

    deinit { accountObservation.dispose(); operation.dispose() }

    func apply(retry: Bool) {
        guard current.accountActive, !current.busy else { return }
        let expectedGeneration = generation
        let target = retry ? true : !current.enabled
        current.busy = true
        current.message = "Застосування…"
        state.set(.single(current))
        operation.set((TraceFoxPrivacyControl.setEnabled(target, network: context.account.network)
        |> deliverOnMainQueue).start(error: { [weak self] error in
            guard let self = self, self.generation == expectedGeneration, self.current.accountActive else { return }
            self.current.busy = false
            switch error {
            case .settingsWriteFailed:
                self.current.enabled = (try? TraceFoxPrivacyRuntime.preferences(network: self.context.account.network).readEnabled()) ?? true
                self.current.message = "Не вдалося завершити збереження налаштувань. Показано поточний стан захисту."
            case .offlineUpdateFailed:
                self.current.enabled = target
                self.current.needsRetry = true
                self.current.message = "Захист увімкнено, але сервер ще не підтвердив статус офлайн. Натисніть повторити."
            }
            self.state.set(.single(self.current))
        }, completed: { [weak self] in
            guard let self = self, self.generation == expectedGeneration, self.current.accountActive else { return }
            self.current = PrivacyScreenState(enabled: target)
            self.current.accountActive = true
            self.state.set(.single(self.current))
        }))
    }
}

private enum PrivacySection: Int32, SGItemListSection { case settings }
private typealias PrivacyEntry = SGItemListUIEntry<PrivacySection, Int, Int, Int, Int, Int>

// Settings entry is part of the native integration candidate.
public func traceFoxPrivacyController(context: AccountContext) -> ViewController {
    let model = PrivacyScreenModel(context: context)
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { action in model.apply(retry: action == 1) })
    let signal = combineLatest(context.sharedContext.presentationData, model.state.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [PrivacyEntry] = [
            .header(id: 0, section: .settings, text: "Режим привида", badge: nil),
            .notice(id: 1, section: .settings, text: "Стан для поточного акаунта: " + (state.enabled ? "увімкнено" : "вимкнено")),
            .notice(id: 2, section: .settings, text: "Приховує набір тексту та нові позначки прочитання, надсилає статус офлайн. Уже відправлені запити можуть завершитися. Надсилання повідомлень може показати вашу активність.")
        ]
        if state.accountActive && !state.busy {
            entries.append(.action(id: 3, section: .settings, actionType: 0, text: state.enabled ? "Вимкнути" : "Увімкнути", kind: .generic))
        }
        if !state.message.isEmpty { entries.append(.notice(id: 4, section: .settings, text: state.message)) }
        if state.accountActive && state.needsRetry && !state.busy {
            entries.append(.action(id: 5, section: .settings, actionType: 1, text: "Повторити перехід в офлайн", kind: .generic))
        }
        let controller = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Приватність TraceFox"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controller, (list, arguments))
    }
    return ItemListController(context: context, state: signal)
}
