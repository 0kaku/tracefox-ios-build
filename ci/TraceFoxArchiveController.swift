import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI

private enum TraceFoxArchiveSection: Int32, SGItemListSection { case messages }
private typealias ArchiveEntry = SGItemListUIEntry<TraceFoxArchiveSection, Int, Int, Int, Int, Int>

public func traceFoxArchiveController(context: AccountContext) -> ViewController {
    let recordsPromise = Promise<([TraceFoxArchiveRecord], Bool, Bool, Int)>()
    var currentRecords: [TraceFoxArchiveRecord] = []
    var shareImpl: ((TraceFoxArchiveRecord) -> Void)?
    var loadMoreImpl: (() -> Void)?
    var refreshImpl: (() -> Void)?
    var loadingMore = false
    var category = 0
    var loadGeneration = 0
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { index in
        if index == -2 { loadMoreImpl?(); return }
        if index == -3 { refreshImpl?(); return }
        let recordIndex = index / 2
        guard currentRecords.indices.contains(recordIndex) else { return }
        if index % 2 == 0 { shareImpl?(currentRecords[recordIndex]) }
    })
    refreshImpl = {
        guard !loadingMore else { return }
        loadingMore = true
        let existing = currentRecords
        let selected = category
        loadGeneration += 1
        let token = loadGeneration
        DispatchQueue(label: "tracefox.archive.browser").async {
            do {
                let store = try TraceFoxLocalArchive.store(mediaBox: context.account.postbox.mediaBox)
                let kind = TraceFoxArchiveCategory(rawValue: selected)!
                let records = try store.records(matching: { record in
                    kind.includes(record) && (kind == .secretChats || record.files.contains(where: { (try? store.mediaURL(name: $0)) != nil }))
                })
                DispatchQueue.main.async {
                    guard token == loadGeneration else { return }
                    loadingMore = false
                    recordsPromise.set(.single((records, false, records.count == 100, selected)))
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == loadGeneration else { return }
                    loadingMore = false
                    recordsPromise.set(.single((existing, true, !existing.isEmpty, selected)))
                }
            }
        }
    }
    refreshImpl?()
    let signal = combineLatest(context.sharedContext.presentationData, recordsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, result -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (records, loadFailed, hasMore, selected) = result
        currentRecords = records
        var entries: [ArchiveEntry] = [
            .header(id: 0, section: .messages, text: "Локальний архів TraceFox", badge: nil),
            .notice(id: 1, section: .messages, text: "Показано копій: \(records.count). Наступні записи можна завантажити нижче. Файли зберігаються лише коли були завантажені до видалення; ліміти: 64 MiB на файл, 1 GiB на архів.")
        ]
        if loadFailed {
            entries.append(.notice(id: 2, section: .messages, text: records.isEmpty ? "Не вдалося відкрити архів. Натисніть «Оновити список копій», щоб спробувати ще раз." : "Не вдалося оновити список або завантажити сторінку. Уже відкриті копії залишилися на екрані; спробуйте ще раз нижче."))
        } else if records.isEmpty {
            entries.append(.notice(id: 2, section: .messages, text: "Збережених копій поки немає."))
        }
        entries.append(.notice(id: 3, section: .messages, text: "Акаунт підключається до бота автоматично. Резервні копії підтримуваних хмарних чатів надсилаються у фоні під час роботи застосунку; секретні чати залишаються локальними."))
        if hasMore { entries.append(.action(id: 5, section: .messages, actionType: -2, text: "Показати наступні 100 копій", kind: .generic)) }
        entries.append(.action(id: 6, section: .messages, actionType: -3, text: "Оновити список копій", kind: .generic))
        let formatter = DateFormatter()
        formatter.dateStyle = .short; formatter.timeStyle = .short
        for (index, record) in records.enumerated() {
            let title = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.timestamp)))
            let recordState = record.deleted ? " · Видалене" : ((record.previousTexts?.isEmpty == false) ? " · Редаговане" : "")
            let lifetime: String
            if record.ttlSeconds == Int32.max { lifetime = " · Один перегляд" }
            else if let ttl = record.ttlSeconds, ttl > 0 { lifetime = " · Таймер \(ttl) с" }
            else { lifetime = "" }
            let history = (record.previousTexts ?? []).suffix(3).reversed().map {
                "\nПопередній текст:\n" + String($0.prefix(1000))
            }.joined()
            entries.append(.notice(id: 10 + index * 3, section: .messages,
                text: title + " · Чат \(record.peer)" + recordState + lifetime + "\n" + String(record.text.prefix(3000)) + history + "\nФайлів: \(record.files.count)"))
            entries.append(.action(id: 11 + index * 3, section: .messages, actionType: index * 2,
                text: "Відкрити / поділитися копією", kind: .generic))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData),
            title: .textWithTabs("Архів TraceFox", TraceFoxArchiveCategory.allCases.map { $0.title }, selected), leftNavigationButton: nil, rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let list = ItemListNodeState(presentationData: ItemListPresentationData(presentationData),
            entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (state, (list, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    loadMoreImpl = {
        guard !loadingMore, let last = currentRecords.last else { return }
        loadingMore = true
        let existing = currentRecords
        let cursor = TraceFoxArchiveCursor(record: last)
        let selected = category
        loadGeneration += 1
        let token = loadGeneration
        DispatchQueue(label: "tracefox.archive.browser.more").async {
            do {
                let store = try TraceFoxLocalArchive.store(mediaBox: context.account.postbox.mediaBox)
                let kind = TraceFoxArchiveCategory(rawValue: selected)!
                let next = try store.records(before: cursor, matching: { record in
                    kind.includes(record) && (kind == .secretChats || record.files.contains(where: { (try? store.mediaURL(name: $0)) != nil }))
                })
                DispatchQueue.main.async {
                    guard token == loadGeneration else { return }
                    loadingMore = false
                    recordsPromise.set(.single((existing + next, false, next.count == 100, selected)))
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == loadGeneration else { return }
                    loadingMore = false
                    recordsPromise.set(.single((existing, true, true, selected)))
                }
            }
        }
    }
    controller.titleControlValueChanged = { index in
        guard TraceFoxArchiveCategory(rawValue: index) != nil, index != category else { return }
        category = index; loadGeneration += 1; loadingMore = false; currentRecords = []
        recordsPromise.set(.single(([], false, false, index)))
        refreshImpl?()
    }
    shareImpl = { [weak controller] record in
        guard let controller = controller else { return }
        var items: [Any] = []
        if !record.text.isEmpty { items.append(record.text) }
        if let history = record.previousTexts, !history.isEmpty {
            items.append("Попередні версії тексту:\n\n" + history.joined(separator: "\n\n———\n\n"))
        }
        if let store = try? TraceFoxLocalArchive.store(mediaBox: context.account.postbox.mediaBox) {
            for name in record.files { if let url = try? store.mediaURL(name: name) { items.append(url) } }
        }
        if items.isEmpty { items.append("Медіа не було доступне для локального збереження.") }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
            y: controller.view.bounds.midY, width: 1, height: 1)
        controller.present(activity, animated: true)
    }
    return controller
}
