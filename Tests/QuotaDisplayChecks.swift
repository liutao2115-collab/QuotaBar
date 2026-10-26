import Foundation
import AppKit
import SwiftUI

// Compile with the production sources (except QuotaBarApp.swift), then run.
// This standalone runner works with Command Line Tools without XCTest.
@main
enum QuotaDisplayChecks {
    @MainActor
    static func store(weeklyMinutes: Int = 10080, weeklyReset: TimeInterval = 7 * 24 * 3600,
                      fiveHourReset: TimeInterval? = 600) -> UsageStore {
        let now = Date()
        let defaults = UserDefaults(suiteName: "QuotaBarChecks-" + UUID().uuidString)!
        defaults.register(defaults: ["automaticSync": false])
        return UsageStore(defaults: defaults, initialSnapshot: UsageSnapshot(
            usedPercent: 4, resetAt: now.addingTimeInterval(weeklyReset),
            capturedAt: now, windowMinutes: weeklyMinutes, source: "Codex 本机",
            shortWindow: fiveHourReset.map {
                UsageWindow(usedPercent: 25, resetAt: now.addingTimeInterval($0), windowMinutes: 300)
            }
        ), startsServices: false)
    }

    @MainActor
    static func main() async throws {
        let both = store()
        precondition(both.menuBarText == "75%" && both.currentWeeklyWindow?.remainingPercent == 96)
        let missing = store(fiveHourReset: nil)
        precondition(missing.menuBarText == "--%" && missing.currentWeeklyWindow != nil)
        let expiredFive = store(fiveHourReset: -1)
        precondition(expiredFive.menuBarText == "--%" && expiredFive.currentWeeklyWindow != nil)
        let expiredWeek = store(weeklyReset: -1)
        precondition(expiredWeek.menuBarText == "75%" && expiredWeek.currentWeeklyWindow == nil)
        let fiveOnly = store(weeklyMinutes: 300, fiveHourReset: nil)
        precondition(fiveOnly.menuBarText == "96%" && fiveOnly.currentWeeklyWindow == nil)
        try checkReader()
        try await checkOfficialClient()
        print("PASS: five-hour menu bar, independent expiry, missing-window handling, reversed windows, and event timestamps")

        if let option = CommandLine.arguments.firstIndex(of: "--render"), option + 1 < CommandLine.arguments.count {
            let directory = URL(fileURLWithPath: CommandLine.arguments[option + 1])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = NSApplication.shared
            for (name, value) in [("normal", both), ("five-hour-pending", expiredFive), ("weekly-pending", expiredWeek)] {
                try render(value, to: directory.appendingPathComponent(name + ".png"))
            }
        }
    }

    static func checkOfficialClient() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/fake-codex.py")
        let executable = root.appendingPathComponent("fake-codex")
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let normal = root.appendingPathComponent("normal")
        let client = CodexUsageClient(executable: executable, stateDirectory: normal, timeout: 2)
        let fresh = try await client.latestUsage(force: true)
        precondition(fresh.fiveHourWindow?.remainingPercent == 96 && fresh.weeklyWindow?.remainingPercent == 86)
        let cached = try await client.latestUsage()
        precondition(cached.capturedAt == fresh.capturedAt)
        let count = try String(contentsOf: normal.appendingPathComponent("calls"), encoding: .utf8)
        precondition(count == "1", "Background refresh must reuse the recent official response")
        _ = try await client.latestUsage(force: true)
        let refreshedCount = try String(contentsOf: normal.appendingPathComponent("calls"), encoding: .utf8)
        precondition(refreshedCount == "2")
        await client.stop()
        _ = try await client.latestUsage(force: true)
        await client.stop()
        let auth = CodexUsageClient(executable: executable, stateDirectory: root.appendingPathComponent("authentication"), timeout: 2)
        do {
            _ = try await auth.latestUsage(force: true)
            preconditionFailure("Authentication errors must not become 100% usage")
        } catch UsageSyncError.notAuthenticated { }
        let timeout = CodexUsageClient(executable: executable, stateDirectory: root.appendingPathComponent("timeout"), timeout: 0.3)
        do {
            _ = try await timeout.latestUsage(force: true)
            preconditionFailure("Missing responses must time out")
        } catch UsageSyncError.timedOut { }
        precondition(CodexUsageResponse.snapshot(from: ["rateLimitsByLimitId": ["codex_other": [:]]]) == nil)
        print("PASS: official RPC, codex bucket selection, query caching, manual refresh, reconnect, authentication errors, timeout")
    }

    static func checkReader() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fixture.jsonl")
        let reset = Date().addingTimeInterval(3600).timeIntervalSince1970
        let five: [String: Any] = ["used_percent": 25, "window_minutes": 300, "resets_at": reset]
        let week: [String: Any] = ["used_percent": 4, "window_minutes": 10080, "resets_at": reset]
        func write(_ limits: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: [
                "timestamp": "2026-10-23T07:13:00.123Z", "payload": ["rate_limits": limits]
            ]).write(to: file)
        }
        try write(["primary": week, "secondary": five])
        guard let both = SessionUsageReader.latestUsage(in: directory) else { preconditionFailure("Missing fixture") }
        precondition(both.fiveHourWindow?.remainingPercent == 75 && both.weeklyWindow?.remainingPercent == 96)
        precondition(abs(both.capturedAt.timeIntervalSince1970 - 1792739580.123) < 0.001)
        try write(["primary": five])
        let single = SessionUsageReader.latestUsage(in: directory)
        precondition(single?.fiveHourWindow?.remainingPercent == 75 && single?.weeklyWindow == nil)
    }

    @MainActor
    static func render(_ store: UsageStore, to url: URL) throws {
        let view = NSHostingView(rootView: QuotaMenuView().environmentObject(store).environment(\.colorScheme, .light))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("No preview bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("No preview PNG") }
        try png.write(to: url)
        print("Rendered \(url.lastPathComponent): \(size)")
    }
}
