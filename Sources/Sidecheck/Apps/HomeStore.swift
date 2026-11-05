import SwiftUI

/// Owns the home-screen state: which widgets occupy the home slots and
/// whether the home screen is in edit ("jiggle") mode. Slot assignments
/// persist in UserDefaults.
@MainActor
final class HomeStore: ObservableObject {
    static let slotsKey = "homeWidgetSlots"

    @Published var widgetSlots: [WidgetKind?] {
        didSet { persist() }
    }

    @Published var isEditMode = false

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.slotsKey) ?? ""
        let kinds = raw.split(separator: ",").map { WidgetKind(rawValue: String($0)) }
        widgetSlots = kinds.isEmpty ? [WidgetKind.monitor, WidgetKind.battery] : kinds
    }

    func assign(slot: Int, kind: WidgetKind?) {
        guard widgetSlots.indices.contains(slot) else { return }
        widgetSlots[slot] = kind
    }

    private func persist() {
        let raw = widgetSlots.map { $0?.rawValue ?? "" }.joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: Self.slotsKey)
    }
}
