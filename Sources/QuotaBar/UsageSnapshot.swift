import Foundation

struct UsageSnapshot: Codable, Sendable, Equatable {
    let usedPercent: Double
    let resetAt: Date
    let capturedAt: Date
    let windowMinutes: Int
    let source: String

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var isWeekly: Bool {
        windowMinutes >= 6 * 24 * 60
    }
}
