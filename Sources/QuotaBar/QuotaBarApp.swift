import AppKit
import Combine
import SwiftUI

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(QuotaBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class QuotaBarAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = UsageStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private weak var menuBarLabel: NSTextField?
    private var snapshotObservation: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var isMenuTracking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "QuotaBar.RemainingUsage"
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.title = ""
            button.toolTip = "Codex 5 小时剩余用量"

            let label = NSTextField(labelWithString: "--")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .medium
            )
            label.textColor = .labelColor
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1

            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 0),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -0.5)
            ])
            menuBarLabel = label
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: QuotaMenuView().environmentObject(store)
        )

        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(applicationResignedActive),
                                  name: NSApplication.didResignActiveNotification, object: NSApp)
        notifications.addObserver(self, selector: #selector(menuTrackingBegan),
                                  name: NSMenu.didBeginTrackingNotification, object: nil)
        notifications.addObserver(self, selector: #selector(menuTrackingEnded),
                                  name: NSMenu.didEndTrackingNotification, object: nil)

        snapshotObservation = Publishers.CombineLatest(store.$snapshot, store.$displayTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusTitle()
            }

        updateStatusTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeDismissalMonitors()
        NotificationCenter.default.removeObserver(self)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func updateStatusTitle() {
        guard let statusItem, let button = statusItem.button else { return }

        let text = store.menuBarText
        let label = menuBarLabel ?? button.subviews.compactMap { $0 as? NSTextField }.first

        button.title = ""
        label?.stringValue = text

        let textWidth = ceil(
            (text as NSString).size(withAttributes: [
                .font: label?.font ?? NSFont.monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .medium
                )
            ]).width
        )
        statusItem.length = max(textWidth + 2, 20)
        let accessibilityLabel = store.isAwaitingFreshData
            ? "Codex 5 小时用量待更新"
            : "Codex 5 小时剩余 \(store.menuBarText)"
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Accessory apps need key focus for native keyboard dismissal.
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        removeDismissalMonitors()
        // Observe only outside mouse clicks, never global keyboard input.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.popover.isShown, !self.isMenuTracking,
                      event.keyCode == 53,
                      event.window === self.popover.contentViewController?.view.window else { return false }
                self.closePopover()
                return true
            }
            return handled ? nil : event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissalMonitors()
        isMenuTracking = false
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func removeDismissalMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        outsideClickMonitor = nil
        escapeMonitor = nil
    }

    @objc private func applicationResignedActive(_ notification: Notification) {
        closePopover()
    }

    @objc private func menuTrackingBegan(_ notification: Notification) {
        isMenuTracking = true
    }

    @objc private func menuTrackingEnded(_ notification: Notification) {
        isMenuTracking = false
    }
}
