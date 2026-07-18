import Foundation

struct LRUCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private let maxSize: Int

    init(maxSize: Int) {
        self.maxSize = max(1, maxSize)
    }

    var count: Int { values.count }

    subscript(key: Key) -> Value? {
        mutating get {
            get(key)
        }
        set {
            if let newValue {
                set(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    mutating func get(_ key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ value: Value, forKey key: Key) {
        if values[key] != nil {
            values[key] = value
            touch(key)
            return
        }

        while order.count >= maxSize, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }

        values[key] = value
        order.append(key)
    }

    mutating func removeValue(forKey key: Key) {
        values.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    mutating func removeAll() {
        values.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
