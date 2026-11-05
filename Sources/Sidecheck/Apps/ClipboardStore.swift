import AppKit
import SwiftUI

/// Captures text the user copies anywhere on the system by watching the
/// general pasteboard's change count. Polls for the app's lifetime (the check
/// is one integer comparison per tick) so copies made while the panel is
/// closed are still captured. Strings and links only; history persists in
/// UserDefaults.
@MainActor
final class ClipboardStore: ObservableObject {
    struct Item: Codable, Identifiable, Equatable {
        var id: Int
        var text: String
        var date: Date
    }

    static let itemsKey = "clipboardItems"
    static let capacity = 50
    /// Skip pathological pasteboard payloads (huge file dumps) entirely.
    private static let maxCapturedLength = 100_000
    private static let pollInterval: TimeInterval = 0.4

    @Published private(set) var items: [Item] = []
    /// Briefly the id of a just re-copied item, for UI feedback.
    @Published var flashID: Int?

    private var lastChangeCount = 0
    private var nextID = 1
    private var timer: Timer?
    private var flashTask: DispatchWorkItem?

    /// Diagnostics: the pasteboard poller runs for the app's lifetime.
    var isPolling: Bool { timer != nil }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
            nextID = (saved.map(\.id).max() ?? 0) + 1
        }
    }

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxCapturedLength,
              text != items.first?.text else { return }

        items.insert(Item(id: nextID, text: text, date: Date()), at: 0)
        nextID += 1
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        persist()
    }

    /// Re-copies an item and bumps it to the top. Our own pasteboard write
    /// increments changeCount — absorb it so we don't re-capture the copy.
    func recopy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var refreshed = item
            refreshed.date = Date()
            items.remove(at: index)
            items.insert(refreshed, at: 0)
            persist()
        }

        flashID = item.id
        flashTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            if self?.flashID == item.id { self?.flashID = nil }
        }
        flashTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }
}
