import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?
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

    private let defaults = UserDefaults.standard
    private var lastNotifiedResetAt: Date?
    private var statusClearTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var refreshDebounceTask: Task<Void, Never>?
    private var sessionUsageWatcher: SessionUsageWatcher?

    private enum Keys {
        static let snapshot = "savedSnapshot"
        static let manualSnapshot = "manualSnapshot"
        static let warningThreshold = "warningThreshold"
        static let automaticSync = "automaticSync"
        static let lastNotifiedResetAt = "lastNotifiedResetAt"
    }

    init() {
        warningThreshold = defaults.object(forKey: Keys.warningThreshold) as? Double ?? 20
        automaticSync = defaults.object(forKey: Keys.automaticSync) as? Bool ?? true
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        lastNotifiedResetAt = defaults.object(forKey: Keys.lastNotifiedResetAt) as? Date
        snapshot = Self.decode(UsageSnapshot.self, from: defaults.data(forKey: Keys.snapshot))
        startAutomaticRefresh()
        refresh()
    }

    var currentSnapshot: UsageSnapshot? {
        guard let snapshot else { return nil }
        guard Date() >= snapshot.resetAt else { return snapshot }

        let windowSeconds = TimeInterval(max(snapshot.windowMinutes, 1) * 60)
        let elapsed = Date().timeIntervalSince(snapshot.resetAt)
        let completedWindows = floor(elapsed / windowSeconds) + 1
        let nextReset = snapshot.resetAt.addingTimeInterval(completedWindows * windowSeconds)

        return UsageSnapshot(
            usedPercent: 0,
            resetAt: nextReset,
            capturedAt: snapshot.capturedAt,
            windowMinutes: snapshot.windowMinutes,
            source: "新周期"
        )
    }

    var isShowingProjectedReset: Bool {
        guard let snapshot else { return false }
        return Date() >= snapshot.resetAt
    }

    var menuBarText: String {
        guard let snapshot = currentSnapshot else { return "--" }
        return "\(Int(snapshot.remainingPercent.rounded()))%"
    }

    var statusSymbol: String {
        guard let remaining = currentSnapshot?.remainingPercent else { return "circle.dashed" }
        switch remaining {
        case ..<10: return "exclamationmark.circle.fill"
        case ..<warningThreshold: return "circle.lefthalf.filled"
        default: return "circle.inset.filled"
        }
    }

    var footerText: String {
        if isShowingProjectedReset {
            return "额度已重置"
        }
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        guard let snapshot = currentSnapshot else {
            return "等待首次更新"
        }
        return "已更新 · \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))"
    }

    func refresh() {
        guard automaticSync else {
            loadManualSnapshot()
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        statusMessage = nil
        Task {
            let latest = await Task.detached(priority: .utility) {
                SessionUsageReader.latestWeeklyUsage()
            }.value

            isRefreshing = false
            if let latest {
                apply(latest)
                statusMessage = nil
            } else {
                statusMessage = snapshot == nil ? "暂未找到本周用量" : nil
            }
        }
    }

    func refreshSoon() {
        guard automaticSync else { return }
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func applyManual(remainingPercent: Double, resetAt: Date) {
        let manual = UsageSnapshot(
            usedPercent: 100 - remainingPercent,
            resetAt: resetAt,
            capturedAt: Date(),
            windowMinutes: 7 * 24 * 60,
            source: "手动校准"
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

    private func stopAutomaticRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        sessionUsageWatcher?.stop()
        sessionUsageWatcher = nil
    }

    private func apply(_ newSnapshot: UsageSnapshot) {
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
        guard let snapshot = currentSnapshot,
              snapshot.remainingPercent <= warningThreshold,
              lastNotifiedResetAt != snapshot.resetAt else { return }

        let content = UNMutableNotificationContent()
        content.title = "本周用量即将用完"
        content.body = "当前剩余 \(Int(snapshot.remainingPercent.rounded()))%，请合理安排接下来的使用。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "quota-low-\(snapshot.resetAt.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        lastNotifiedResetAt = snapshot.resetAt
        defaults.set(snapshot.resetAt, forKey: Keys.lastNotifiedResetAt)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
