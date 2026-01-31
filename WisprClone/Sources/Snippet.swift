import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID
    var trigger: String
    var expansion: String
    var createdAt: Date
    
    init(id: UUID = UUID(), trigger: String, expansion: String, createdAt: Date = Date()) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.createdAt = createdAt
    }
}
