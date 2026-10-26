import AppKit
import SwiftUI

struct QuotaMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualEditorVisible = false
    @State private var manualRemaining = 50.0
    @State private var manualReset = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var manualFiveHourRemaining = 50.0
    @State private var manualFiveHourReset = Date().addingTimeInterval(5 * 60 * 60)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if manualEditorVisible {
                manualEditor
            } else if store.currentSnapshot != nil {
                usageContent
            } else {
                emptyContent
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .onAppear {
            store.refreshSoon(forceLive: true)
            if let weekly = store.currentWeeklyWindow {
                manualRemaining = weekly.remainingPercent
                manualReset = weekly.resetAt
            }
            if let fiveHour = store.currentFiveHourWindow {
                manualFiveHourRemaining = fiveHour.remainingPercent
                manualFiveHourReset = fiveHour.resetAt
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("剩余用量")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                store.refresh(forceLive: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("向官方查询最新额度")

            Menu {
                Toggle("自动更新", isOn: $store.automaticSync)
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { store.launchAtLoginEnabled },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                if store.launchAtLoginNeedsApproval {
                    Button {
                        store.openLoginItemsSettings()
                    } label: {
                        Label("打开登录项设置", systemImage: "gear")
                    }
                }
                Button {
                    store.requestNotifications()
                } label: {
                    Label("5 小时低于 20% 时提醒", systemImage: "bell")
                }
                Button("手动校准…") { manualEditorVisible.toggle() }
                Button {
                    store.openUsagePage()
                } label: {
                    Label("查看网页版", systemImage: "safari")
                }
                Divider()
                Button("退出 QuotaBar", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var usageContent: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 15) {
                quotaColumn(
                    title: "5 小时剩余",
                    window: store.currentFiveHourWindow,
                    recorded: store.snapshot?.fiveHourWindow
                )

                Divider()
                    .frame(height: 81)
                    .padding(.top, 2)

                quotaColumn(
                    title: "一周剩余",
                    window: store.currentWeeklyWindow,
                    recorded: store.snapshot?.weeklyWindow
                )
            }

            Divider()

            HStack {
                Text(store.footerText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(store.syncIssue ?? store.footerText)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func quotaColumn(title: String, window: UsageWindow?, recorded: UsageWindow?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let window {
                    Text("\(Int(window.remainingPercent.rounded()))")
                        .font(.system(size: 46, weight: .medium))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("待更新")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 49, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(window.map { "重置 " + resetDescription($0.resetAt) }
                ?? (recorded == nil ? "等待用量数据" : "已重置，等待更新"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Text("暂时没有用量数据")
                .font(.system(size: 13, weight: .semibold))
            Text("开始一次 Codex 对话后重新检查")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button("重新检查") { store.refresh(forceLive: true) }
                Button("手动输入") { manualEditorVisible = true }
            }
            .controlSize(.small)
        }
        .padding(20)
    }

    private var manualEditor: some View {
        VStack(spacing: 12) {
            manualPercentageRow(title: "5 小时剩余", value: $manualFiveHourRemaining)
            DatePicker("5 小时重置", selection: $manualFiveHourReset, displayedComponents: [.date, .hourAndMinute])
            Divider()
            manualPercentageRow(title: "一周剩余", value: $manualRemaining)
            DatePicker("一周重置", selection: $manualReset, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Button("取消") { manualEditorVisible = false }
                Spacer()
                Button("应用") {
                    store.automaticSync = false
                    store.applyManual(
                        remainingPercent: manualRemaining,
                        resetAt: manualReset,
                        fiveHourRemaining: manualFiveHourRemaining,
                        fiveHourReset: manualFiveHourReset
                    )
                    manualEditorVisible = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(20)
    }

    private func manualPercentageRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...100, step: 1)
            Text("\(Int(value.wrappedValue))%")
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func resetDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: date)
        }
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
