import Foundation
import SwiftData

@Model
final class Pinboard: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date
    var itemIDsRaw: String

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#6C7BFF",
        itemIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
        self.itemIDsRaw = itemIDs.map(\.uuidString).joined(separator: "\n")
    }

    var itemIDs: [UUID] {
        get {
            itemIDsRaw
                .split(whereSeparator: \.isNewline)
                .compactMap { UUID(uuidString: String($0)) }
        }
        set {
            itemIDsRaw = newValue.map(\.uuidString).joined(separator: "\n")
            updatedAt = Date()
        }
    }

    func contains(_ item: ClipItem) -> Bool {
        itemIDs.contains(item.id)
    }
}
