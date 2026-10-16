import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI

private final class TraceFoxUpdatesModel {
    let state = Promise<(String, URL?, Bool)>()
    private var task: URLSessionDataTask?
    private var generation = 0
    private let installed = Int64(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    init() { state.set(.single(("Встановлена збірка: \(installed.map(String.init) ?? "невідома"). Перевірка звертається до GitHub лише після натискання кнопки.", nil, false))) }
    deinit { task?.cancel() }
    func cancel() { generation += 1; task?.cancel(); task = nil; state.set(.single(("Перевірку зупинено. Натисніть кнопку, щоб перевірити знову.", nil, false))) }
    func check() {
        cancel()
        guard let installed = installed else { state.set(.single(("Не вдалося визначити номер встановленої збірки.", nil, false))); return }
        let token = generation
        state.set(.single(("Перевіряємо нову версію…", nil, true)))
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/0kaku/tracefox-ios-build/releases/latest")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFox-iOS", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.task = nil
                let code = (response as? HTTPURLResponse)?.statusCode
                if error != nil { self.state.set(.single(("Не вдалося перевірити оновлення. Спробуйте ще раз.", nil, false))); return }
                if code == 404 { self.state.set(.single(("Опублікованих версій для оновлення поки немає.", nil, false))); return }
                guard code == 200, let data = data else { self.state.set(.single(("Сервіс оновлень тимчасово недоступний.", nil, false))); return }
                do {
                    if let update = try TraceFoxUpdateInfo.parse(data, installedBuild: installed) {
                        self.state.set(.single(("Доступна збірка \(update.build). Відкрийте сторінку релізу, завантажте IPA та встановіть її обраним способом підпису. Наявність IPA не підтверджує сумісність підпису з цим iPhone.", update.page, false)))
                    } else { self.state.set(.single(("Новішої опублікованої збірки немає.", nil, false))) }
                } catch { self.state.set(.single(("Дані релізу не відповідають формату оновлень TraceFox.", nil, false))) }
            }
        }
        task?.resume()
    }
}
private enum UpdatesSection: Int32, SGItemListSection { case updates }
private typealias UpdatesEntry = SGItemListUIEntry<UpdatesSection, Int, Int, Int, Int, Int>
public func traceFoxUpdatesController(context: AccountContext) -> ViewController {
    let model = TraceFoxUpdatesModel()
    var download: URL?
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { action in
        if action == 0 { model.check() }
        else if let url = download { context.sharedContext.applicationBindings.openUrl(url.absoluteString) }
    })
    let signal = combineLatest(context.sharedContext.presentationData, model.state.get()) |> deliverOnMainQueue
    |> map { presentationData, value -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (message, url, busy) = value; download = url
        var entries: [UpdatesEntry] = [.notice(id: 0, section: .updates, text: message)]
        if !busy { entries.append(.action(id: 1, section: .updates, actionType: 0, text: "Перевірити оновлення", kind: .generic)) }
        if url != nil { entries.append(.action(id: 2, section: .updates, actionType: 1, text: "Відкрити завантаження оновлення", kind: .generic)) }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Оновлення TraceFox"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (state, (list, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { [weak model] _ in model?.cancel() }
    return controller
}
