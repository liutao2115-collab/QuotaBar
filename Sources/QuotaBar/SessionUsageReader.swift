import Foundation

enum SessionUsageReader {
    private struct WindowCandidate {
        let usedPercent: Double
        let windowMinutes: Int
        let resetAt: Date
    }

    static func latestWeeklyUsage() -> UsageSnapshot? {
        let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        var recentFiles: [(url: URL, modified: Date)] = []

        // A weekly allowance cannot be affected by sessions older than two weeks.
        // Restricting the scan keeps the menu bar utility quiet even after years of use.
        let calendar = Calendar(identifier: .gregorian)
        for dayOffset in 0...14 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else { continue }

            let dayURL = sessionsURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)

            let files = (try? FileManager.default.contentsOfDirectory(
                at: dayURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in files where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                recentFiles.append((url, values.contentModificationDate ?? .distantPast))
            }
        }

        recentFiles.sort { $0.modified > $1.modified }

        for file in recentFiles.prefix(80) {
            if let snapshot = readLatestSnapshot(from: file.url, modifiedAt: file.modified) {
                return snapshot
            }
        }
        return nil
    }

    private static func readLatestSnapshot(from url: URL, modifiedAt: Date) -> UsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let maximumBytes: UInt64 = 3 * 1024 * 1024
        let fileSize = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: fileSize > maximumBytes ? fileSize - maximumBytes : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }

            let candidates = ["primary", "secondary", "individual_limit"].compactMap {
                windowCandidate(from: limits[$0])
            }

            // Codex normally reports a five-hour and a seven-day window. The largest
            // window is the weekly allowance the menu bar is intended to show.
            guard let weekly = candidates
                .filter({ $0.windowMinutes >= 6 * 24 * 60 })
                .max(by: { $0.windowMinutes < $1.windowMinutes }) else { continue }

            return UsageSnapshot(
                usedPercent: weekly.usedPercent,
                resetAt: weekly.resetAt,
                capturedAt: modifiedAt,
                windowMinutes: weekly.windowMinutes,
                source: "Codex 本机状态"
            )
        }
        return nil
    }

    private static func windowCandidate(from value: Any?) -> WindowCandidate? {
        guard let dictionary = value as? [String: Any],
              let used = number(dictionary["used_percent"]),
              let minutes = number(dictionary["window_minutes"]),
              let resetEpoch = number(dictionary["resets_at"]) else { return nil }

        return WindowCandidate(
            usedPercent: used,
            windowMinutes: Int(minutes),
            resetAt: Date(timeIntervalSince1970: resetEpoch)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
