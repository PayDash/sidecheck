import SwiftUI

/// Owns the home-screen state: how many widget slots exist, which widgets
/// occupy them, and whether the home screen is in edit ("jiggle") mode.
/// Slot count and assignments persist in UserDefaults.
@MainActor
final class HomeStore: ObservableObject {
    static let slotsKey = "homeWidgetSlots"
    static let slotCountKey = "homeSlotCount"

    @Published var widgetSlots: [WidgetKind?] {
        didSet { persist() }
    }

    @Published var slotCount: Int {
        didSet {
            // Grow with empty slots / trim from the end.
            while widgetSlots.count < slotCount { widgetSlots.append(nil) }
            if widgetSlots.count > slotCount {
                widgetSlots.removeLast(widgetSlots.count - slotCount)
            }
            persist()
        }
    }

    /// Slots actually rendered — the current theme may cap this below
    /// `slotCount` (phone-card frames fit 2). Extra assignments are kept so
    /// switching to a wider theme restores them.
    @Published private(set) var activeLimit: Int = Config.slotCountRange.upperBound

    @Published var isEditMode = false

    var effectiveSlots: [WidgetKind?] {
        Array(widgetSlots.prefix(activeLimit))
    }

    /// Called when the theme changes (and once at launch).
    func applyThemeLimit(_ limit: Int) {
        activeLimit = min(max(limit, Config.slotCountRange.lowerBound), Config.slotCountRange.upperBound)
    }

    init() {
        let defaults = UserDefaults.standard
        let persistedCount = defaults.object(forKey: Self.slotCountKey) as? Int ?? 2
        let initialCount = min(max(persistedCount, Config.slotCountRange.lowerBound), Config.slotCountRange.upperBound)
        slotCount = initialCount

        let raw = defaults.string(forKey: Self.slotsKey)
        var kinds: [WidgetKind?] = raw.map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map { WidgetKind(rawValue: String($0)) }
        } ?? []

        if raw == nil, initialCount == 2 {
            // First launch: two sensible defaults.
            kinds = [WidgetKind.monitor, WidgetKind.battery]
        }
        while kinds.count < initialCount { kinds.append(nil) }
        if kinds.count > initialCount { kinds.removeLast(kinds.count - initialCount) }
        widgetSlots = kinds
    }

    func assign(slot: Int, kind: WidgetKind?) {
        guard slot < activeLimit, widgetSlots.indices.contains(slot) else { return }
        widgetSlots[slot] = kind
    }

    /// Swaps a slot with its left/right neighbor (within the active limit).
    func move(slot: Int, direction: Int) {
        let target = slot + direction
        guard slot < activeLimit, target < activeLimit,
              widgetSlots.indices.contains(slot), widgetSlots.indices.contains(target) else { return }
        widgetSlots.swapAt(slot, target)
    }

    private func persist() {
        let raw = widgetSlots.map { $0?.rawValue ?? "" }.joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: Self.slotsKey)
        UserDefaults.standard.set(slotCount, forKey: Self.slotCountKey)
    }
}
