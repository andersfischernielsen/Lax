import Observation

/// A dictionary observed one key at a time: a view that reads one key redraws only when
/// that key changes, not when any other does. A plain dictionary property is a single
/// observed value, so one new entry would redraw every view that reads any entry.
@MainActor
final class KeyedStore<Key: Hashable, Value> {
    @Observable
    final class Slot {
        var value: Value?
    }

    private var slots: [Key: Slot] = [:]

    subscript(key: Key) -> Value? {
        get { slot(key).value }
        set { slot(key).value = newValue }
    }

    /// Keys that have a value. Not observed; for bookkeeping, not for views.
    var keys: [Key] {
        slots.compactMap { $0.value.value == nil ? nil : $0.key }
    }

    func update(_ key: Key, _ change: (inout Value) -> Void) {
        guard var value = self[key] else { return }
        change(&value)
        self[key] = value
    }

    private func slot(_ key: Key) -> Slot {
        if let slot = slots[key] { return slot }
        let slot = Slot()
        slots[key] = slot
        return slot
    }
}
