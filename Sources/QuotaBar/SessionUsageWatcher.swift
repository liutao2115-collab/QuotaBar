import CoreServices
import Foundation

final class SessionUsageWatcher {
    private let sessionsURL: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.local.quotabar.session-usage-watcher")
    private var stream: FSEventStreamRef?

    init(
        sessionsURL: URL = SessionUsageReader.sessionsDirectoryURL,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        self.sessionsURL = sessionsURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        try? FileManager.default.createDirectory(
            at: sessionsURL,
            withIntermediateDirectories: true
        )

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = NSArray(array: [sessionsURL.path])
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func notifyChanged() {
        Task { @MainActor [onChange] in
            onChange()
        }
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<SessionUsageWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.notifyChanged()
    }
}
