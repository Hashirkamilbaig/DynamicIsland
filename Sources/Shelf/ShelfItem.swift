import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let originalName: String
    let cachedURL: URL
    let createdAt: Date
    let expiresAt: Date
    let contentType: UTType?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var remainingSeconds: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}
