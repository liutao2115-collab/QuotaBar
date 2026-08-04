import AppKit
import SwiftUI

struct QuotaMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualEditorVisible = false
    @State private var manualRemaining = 50.0
    @State private var manualReset = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot = store.currentSnapshot {
                usageContent(snapshot)
            } else {
                emptyContent
            }
        }
        .frame(width: 292)
        .background(.regularMaterial)
        .onReceive(refreshTimer) { _ in store.refresh() }
        .onAppear {
            if let snapshot = store.currentSnapshot {
                manualRemaining = snapshot.remainingPercent
                manualReset = snapshot.resetAt
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.inset.filled")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            Text("本周用量")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                store.refresh()
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
            .help("立即更新")

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
                    Label("低于 20% 时提醒", systemImage: "bell")
                }

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
            .fixedSize()
            .help("更多")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 15) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(snapshot.remainingPercent.rounded()))")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text("%")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("剩余")
                        .font(.system(size: 12, weight: .medium))
                    Text("本周额度")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: snapshot.remainingPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(accentColor)
                .accessibilityLabel("本周剩余用量")
                .accessibilityValue("百分之 \(Int(snapshot.remainingPercent.rounded()))")

            HStack(spacing: 0) {
                compactMetric(
                    title: "已用",
                    value: "\(Int(snapshot.usedPercent.rounded()))%"
                )

                Divider()
                    .frame(height: 28)
                    .padding(.horizontal, 16)

                compactMetric(
                    title: "重置",
                    value: resetDescription(snapshot.resetAt)
                )

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: store.isShowingProjectedReset
                    ? "arrow.counterclockwise.circle.fill"
                    : "checkmark.circle.fill")
                    .foregroundStyle(store.isShowingProjectedReset ? .blue : .green)
                    .font(.system(size: 10))

                Text(store.footerText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
        }
        .padding(14)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 13) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(spacing: 3) {
                Text("暂时没有用量数据")
                    .font(.system(size: 13, weight: .semibold))
                Text("开始一次 Codex 对话后重新检查")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("重新检查") { store.refresh() }
                Button("手动输入") { manualEditorVisible.toggle() }
            }
            .controlSize(.small)

            if manualEditorVisible {
                Divider()

                HStack {
                    Text("剩余")
                    Slider(value: $manualRemaining, in: 0...100, step: 1)
                    Text("\(Int(manualRemaining))%")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }

                DatePicker(
                    "重置",
                    selection: $manualReset,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Button("应用") {
                    store.automaticSync = false
                    store.applyManual(remainingPercent: manualRemaining, resetAt: manualReset)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .font(.system(size: 11))
        .padding(16)
    }

    private var accentColor: Color {
        guard let remaining = store.currentSnapshot?.remainingPercent else { return .secondary }
        if remaining < 10 { return .red }
        if remaining < store.warningThreshold { return .orange }
        return .green
    }

    private func resetDescription(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今天 " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
