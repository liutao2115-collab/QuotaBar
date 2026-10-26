import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var displayTick = Date()
    @Published private(set) var statusMessage: String?
    @Published private(set) var syncIssue: String?
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginNeedsApproval: Bool
    @Published var warningThreshold: Double {
        didSet {
            defaults.set(warningThreshold, forKey: Keys.warningThreshold)
            checkLowUsageNotification()
        }
    }
    @Published var automaticSync: Bool {
        didSet {
            defaults.set(automaticSync, forKey: Keys.automaticSync)
            automaticSync ? startAutomaticRefresh() : stopAutomaticRefresh()
            automaticSync ? refresh() : loadManualSnapshot()
        }
    }

    private let defaults: UserDefaults
    private var lastNotifiedResetAt: Date?
    private var statusClearTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var displayTimer: Timer?
    private var refreshDebounceTask: Task<Void, Never>?
    private var sessionUsageWatcher: SessionUsageWatcher?
    private let liveUsageClient = CodexUsageClient()

    private enum Keys {
        static let snapshot = "savedSnapshot"
        static let manualSnapshot = "manualSnapshot"
        static let warningThreshold = "warningThreshold"
        static let automaticSync = "automaticSync"
        static let lastNotifiedResetAt = "lastNotifiedFiveHourResetAt"
    }

    init(defaults: UserDefaults = .standard, initialSnapshot: UsageSnapshot? = nil, startsServices: Bool = true) {
        self.defaults = defaults
        warningThreshold = defaults.object(forKey: Keys.warningThreshold) as? Double ?? 20
        automaticSync = defaults.object(forKey: Keys.automaticSync) as? Bool ?? true
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        lastNotifiedResetAt = defaults.object(forKey: Keys.lastNotifiedResetAt) as? Date
        snapshot = initialSnapshot ?? Self.decode(UsageSnapshot.self, from: defaults.data(forKey: Keys.snapshot))
        guard startsServices else { return }
        startDisplayTimer()
        startAutomaticRefresh()
        refresh(forceLive: true)
    }

    var currentSnapshot: UsageSnapshot? {
        snapshot
    }

    var isAwaitingFreshData: Bool {
        currentFiveHourWindow == nil
    }

    var currentFiveHourWindow: UsageWindow? {
        guard let window = snapshot?.fiveHourWindow, window.resetAt > displayTick else { return nil }
        return window
    }

    var currentWeeklyWindow: UsageWindow? {
        guard let window = snapshot?.weeklyWindow, window.resetAt > displayTick else { return nil }
        return window
    }

    var menuBarText: String {
        guard let window = currentFiveHourWindow else { return "--%" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    var isDataStale: Bool {
        if snapshot != nil && (currentFiveHourWindow == nil || currentWeeklyWindow == nil) { return true }
        guard let snapshot = currentSnapshot else { return false }
        return displayTick.timeIntervalSince(snapshot.capturedAt) > 30 * 60
    }

    var statusSymbol: String {
        guard let remaining = currentFiveHourWindow?.remainingPercent else { return "circle.dashed" }
        switch remaining {
        case ..<10: return "exclamationmark.circle.fill"
        case ..<warningThreshold: return "circle.lefthalf.filled"
        default: return "circle.inset.filled"
        }
    }

    var footerText: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        guard let snapshot = currentSnapshot else {
            return "等待首次更新"
        }
        let source = snapshot.source == "Codex 本机状态" ? "Codex 本机" : snapshot.source
        let updateTime = snapshot.capturedAt.formatted(date: .omitted, time: .shortened)
        if syncIssue != nil && isDataStale {
            return "\(source) · \(updateTime) · 等待同步"
        }
        if isDataStale {
            return "\(source) · \(updateTime) 的数据，待更新"
        }
        return "\(source) · 更新于 \(updateTime)"
    }

    func refresh(forceLive: Bool = false) {
        guard automaticSync else {
            loadManualSnapshot()
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        statusMessage = nil
        Task {
            var official: UsageSnapshot?
            do {
                official = try await liveUsageClient.latestUsage(force: forceLive)
                syncIssue = nil
            } catch {
                syncIssue = (error as? UsageSyncError ?? .unavailable).message
            }
            // Avoid repeatedly scanning session files when official data is available.
            let local: UsageSnapshot?
            if official == nil {
                local = await Task.detached(priority: .utility) {
                    SessionUsageReader.latestUsage()
                }.value
            } else {
                local = nil
            }

            isRefreshing = false
            // A manual edit made during the query must not be overwritten.
            guard automaticSync else { return }
            let previous = snapshot?.source == "手动校准" ? nil : snapshot
            let latest = [official, local, previous].compactMap { $0 }
                .max { $0.capturedAt < $1.capturedAt }
            if let latest {
                apply(latest)
                statusMessage = nil
            } else {
                statusMessage = syncIssue ?? "暂未找到用量数据"
            }
        }
    }

    func refreshSoon(forceLive: Bool = false) {
        guard automaticSync else { return }
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.refresh(forceLive: forceLive)
        }
    }

    func applyManual(remainingPercent: Double, resetAt: Date, fiveHourRemaining: Double, fiveHourReset: Date) {
        let manual = UsageSnapshot(
            usedPercent: 100 - remainingPercent,
            resetAt: resetAt,
            capturedAt: Date(),
            windowMinutes: 7 * 24 * 60,
            source: "手动校准",
            shortWindow: UsageWindow(usedPercent: 100 - fiveHourRemaining, resetAt: fiveHourReset, windowMinutes: 300)
        )
        defaults.set(Self.encode(manual), forKey: Keys.manualSnapshot)
        apply(manual)
        statusMessage = nil
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.showTemporaryStatus(granted ? "低用量提醒已开启" : "请在系统设置中允许通知")
            }
        }
    }

    func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/codex/settings/usage") else { return }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            updateLaunchAtLoginStatus()
            showTemporaryStatus(launchAtLoginNeedsApproval
                ? "请在系统设置中允许登录时启动"
                : (launchAtLoginEnabled ? "已开启登录时启动" : "已关闭登录时启动"))
        } catch {
            updateLaunchAtLoginStatus()
            showTemporaryStatus("无法更改登录启动设置")
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func loadManualSnapshot() {
        if let manual = Self.decode(UsageSnapshot.self, from: defaults.data(forKey: Keys.manualSnapshot)) {
            apply(manual)
            statusMessage = "正在使用手动校准"
        } else if snapshot == nil {
            statusMessage = "请先设置一次剩余用量"
        }
    }

    private func startAutomaticRefresh() {
        guard automaticSync else { return }

        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        sessionUsageWatcher = SessionUsageWatcher { [weak self] in
            Task { @MainActor in
                self?.refreshSoon()
            }
        }
        sessionUsageWatcher?.start()
    }

    private func startDisplayTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.displayTick = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopAutomaticRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        sessionUsageWatcher?.stop()
        sessionUsageWatcher = nil
        Task { await liveUsageClient.stop() }
    }

    private func apply(_ newSnapshot: UsageSnapshot) {
        displayTick = Date()
        snapshot = newSnapshot
        defaults.set(Self.encode(newSnapshot), forKey: Keys.snapshot)
        checkLowUsageNotification()
    }

    private func updateLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func showTemporaryStatus(_ message: String) {
        statusClearTask?.cancel()
        statusMessage = message
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private func checkLowUsageNotification() {
        guard let window = currentFiveHourWindow,
              let snapshot,
              displayTick.timeIntervalSince(snapshot.capturedAt) <= 30 * 60,
              window.remainingPercent <= warningThreshold,
              lastNotifiedResetAt != window.resetAt else { return }

        let content = UNMutableNotificationContent()
        content.title = "5 小时用量即将用完"
        content.body = "5 小时额度剩余 \(Int(window.remainingPercent.rounded()))%。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "quota-five-hour-low-\(window.resetAt.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        lastNotifiedResetAt = window.resetAt
        defaults.set(window.resetAt, forKey: Keys.lastNotifiedResetAt)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
