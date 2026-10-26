import Foundation

struct UsageWindow: Codable, Sendable, Equatable {
    let usedPercent: Double
    let resetAt: Date
    let windowMinutes: Int

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var isFiveHourWindow: Bool {
        windowMinutes == 300
    }
}

struct UsageSnapshot: Codable, Sendable, Equatable {
    let usedPercent: Double
    let resetAt: Date
    let capturedAt: Date
    let windowMinutes: Int
    let source: String
    let shortWindow: UsageWindow?

    init(
        usedPercent: Double,
        resetAt: Date,
        capturedAt: Date,
        windowMinutes: Int,
        source: String,
        shortWindow: UsageWindow? = nil
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.capturedAt = capturedAt
        self.windowMinutes = windowMinutes
        self.source = source
        self.shortWindow = shortWindow
    }

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var isWeekly: Bool {
        windowMinutes >= 6 * 24 * 60
    }

    var weeklyWindow: UsageWindow? {
        guard isWeekly else { return nil }
        return UsageWindow(usedPercent: usedPercent, resetAt: resetAt, windowMinutes: windowMinutes)
    }

    var fiveHourWindow: UsageWindow? {
        if let shortWindow, shortWindow.isFiveHourWindow { return shortWindow }
        guard windowMinutes == 300 else { return nil }
        return UsageWindow(usedPercent: usedPercent, resetAt: resetAt, windowMinutes: windowMinutes)
    }
}
