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
    let cloud = TraceFoxArchiveCloudAction(context: context)
    let recordsPromise = Promise<([TraceFoxArchiveRecord], Bool, Bool)>()
    var currentRecords: [TraceFoxArchiveRecord] = []
    var shareImpl: ((TraceFoxArchiveRecord) -> Void)?
    var loadMoreImpl: (() -> Void)?
    var loadingMore = false
    let arguments = SGItemListArguments<Int, Int, Int, Int, Int>(context: context, action: { index in
        if index == -1 { cloud.send(); return }
        if index == -2 { loadMoreImpl?(); return }
        let recordIndex = index / 2
        guard currentRecords.indices.contains(recordIndex) else { return }
        if index % 2 == 0 { shareImpl?(currentRecords[recordIndex]) }
        else { cloud.send(record: currentRecords[recordIndex]) }
    })
    DispatchQueue(label: "tracefox.archive.browser").async {
        do {
            let records = try TraceFoxLocalArchive.store(mediaBox: context.account.postbox.mediaBox).records()
            recordsPromise.set(.single((records, false, records.count == 100)))
        } catch {
            recordsPromise.set(.single(([], true, false)))
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, recordsPromise.get(), cloud.status.get())
    |> deliverOnMainQueue
    |> map { presentationData, result, cloudStatus -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (records, loadFailed, hasMore) = result
        currentRecords = records
        var entries: [ArchiveEntry] = [
            .header(id: 0, section: .messages, text: "Локальний архів TraceFox", badge: nil),
            .notice(id: 1, section: .messages, text: "Показано копій: \(records.count). Наступні записи можна завантажити нижче. Файли зберігаються лише коли були завантажені до видалення; ліміти: 64 MiB на файл, 1 GiB на архів.")
        ]
        if loadFailed {
            entries.append(.notice(id: 2, section: .messages, text: "Не вдалося відкрити архів. Поверніться та спробуйте ще раз."))
        } else if records.isEmpty {
            entries.append(.notice(id: 2, section: .messages, text: "Збережених копій поки немає."))
        }
        entries.append(.notice(id: 3, section: .messages, text: cloudStatus))
        entries.append(.action(id: 4, section: .messages, actionType: -1, text: "Надіслати наступну текстову подію черги", kind: .generic))
        if hasMore { entries.append(.action(id: 5, section: .messages, actionType: -2, text: "Показати наступні 100 копій", kind: .generic)) }
        let formatter = DateFormatter()
        formatter.dateStyle = .short; formatter.timeStyle = .short
        for (index, record) in records.enumerated() {
            let title = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.timestamp)))
            let lifetime: String
            if record.ttlSeconds == Int32.max { lifetime = " · Один перегляд" }
            else if let ttl = record.ttlSeconds, ttl > 0 { lifetime = " · Таймер \(ttl) с" }
            else { lifetime = "" }
            let history = (record.previousTexts ?? []).suffix(3).reversed().map {
                "\nПопередній текст:\n" + String($0.prefix(1000))
            }.joined()
            entries.append(.notice(id: 10 + index * 3, section: .messages,
                text: title + " · Чат \(record.peer)" + lifetime + "\n" + String(record.text.prefix(3000)) + history + "\nФайлів: \(record.files.count)"))
            entries.append(.action(id: 11 + index * 3, section: .messages, actionType: index * 2,
                text: "Відкрити / поділитися копією", kind: .generic))
            entries.append(.action(id: 12 + index * 3, section: .messages, actionType: index * 2 + 1,
                text: "Надіслати текст копії в хмарний архів", kind: .generic))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData),
            title: .text("Архів TraceFox"), leftNavigationButton: nil, rightNavigationButton: nil,
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
        DispatchQueue(label: "tracefox.archive.browser.more").async {
            do {
                let next = try TraceFoxLocalArchive.store(mediaBox: context.account.postbox.mediaBox).records(before: cursor)
                DispatchQueue.main.async {
                    loadingMore = false
                    recordsPromise.set(.single((existing + next, false, next.count == 100)))
                }
            } catch {
                DispatchQueue.main.async {
                    loadingMore = false
                    recordsPromise.set(.single((existing, true, true)))
                }
            }
        }
    }
    controller.didDisappear = { [weak cloud] _ in cloud?.cancel() }
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
