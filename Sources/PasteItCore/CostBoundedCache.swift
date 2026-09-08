/// Deterministic LRU limits for actor-owned value caches (no shared mutable state).
public struct CostBoundedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let value: Value
        let cost: Int
        var access: UInt64
    }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) public var totalCost = 0
    public var count: Int { entries.count }
    private let countLimit: Int
    private let costLimit: Int

    public init(countLimit: Int, costLimit: Int) {
        self.countLimit = max(0, countLimit)
        self.costLimit = max(0, costLimit)
    }

    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.value
    }

    public mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let previous = entries.removeValue(forKey: key) { totalCost -= previous.cost }
        let cost = max(0, cost)
        guard countLimit > 0, cost <= costLimit else { return }
        while entries.count >= countLimit || totalCost > costLimit - cost {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }),
                  let removed = entries.removeValue(forKey: oldest.key) else { break }
            totalCost -= removed.cost
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, access: clock)
        totalCost += cost
    }
}
