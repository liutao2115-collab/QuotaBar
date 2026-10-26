import Foundation

enum SessionUsageReader {
    static let sessionsDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    private struct WindowCandidate {
        let usedPercent: Double
        let windowMinutes: Int
        let resetAt: Date
    }

    static func latestUsage(in directory: URL = sessionsDirectoryURL) -> UsageSnapshot? {
        let recentFiles = recentSessionFiles(in: directory)

        return recentFiles
            .prefix(160)
            .compactMap { file in
                readLatestSnapshot(from: file.url, modifiedAt: file.modified)
            }
            .max(by: { $0.capturedAt < $1.capturedAt })
    }

    private static func recentSessionFiles(in directory: URL) -> [(url: URL, modified: Date)] {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }

            files.append((url, modified))
        }

        return files.sorted { $0.modified > $1.modified }
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

            let capturedAt = (object["timestamp"] as? String).flatMap(Self.isoDate) ?? modifiedAt
            let candidates = ["primary", "secondary", "individual_limit"].compactMap {
                windowCandidate(from: limits[$0])
            }

            // Identify windows by duration, independently of primary/secondary order.
            let weekly = candidates
                .filter({ $0.windowMinutes >= 6 * 24 * 60 })
                .max(by: { $0.windowMinutes < $1.windowMinutes })
            let shortWindow = candidates
                .first { $0.windowMinutes == 300 }
            guard let baseWindow = weekly ?? shortWindow else { continue }

            return UsageSnapshot(
                usedPercent: baseWindow.usedPercent,
                resetAt: baseWindow.resetAt,
                capturedAt: capturedAt,
                windowMinutes: baseWindow.windowMinutes,
                source: "Codex 本机",
                shortWindow: shortWindow.map {
                    UsageWindow(
                        usedPercent: $0.usedPercent,
                        resetAt: $0.resetAt,
                        windowMinutes: $0.windowMinutes
                    )
                }
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

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
