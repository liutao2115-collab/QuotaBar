import Darwin
import Foundation

enum UsageSyncError: Error {
    case notInstalled, unavailable, timedOut, notAuthenticated, missingLimits

    var message: String {
        switch self {
        case .notInstalled: return "未找到 Codex 客户端，使用本机记录"
        case .notAuthenticated: return "请先在 Codex 登录，当前使用本机记录"
        case .timedOut: return "官方查询超时，保留上次数据"
        case .missingLimits: return "官方暂未返回额度，使用本机记录"
        case .unavailable: return "官方同步暂不可用，保留上次数据"
        }
    }
}

enum CodexUsageResponse {
    static func snapshot(from result: [String: Any], capturedAt: Date = Date()) -> UsageSnapshot? {
        let bucket: [String: Any]?
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any], !buckets.isEmpty {
            bucket = buckets["codex"] as? [String: Any]
        } else {
            let legacy = result["rateLimits"] as? [String: Any]
            let id = legacy?["limitId"] as? String
            bucket = id == nil || id == "codex" ? legacy : nil
        }
        guard let bucket else { return nil }
        let windows = ["primary", "secondary", "individualLimit"].compactMap { key -> UsageWindow? in
            guard let value = bucket[key] as? [String: Any],
                  let used = value["usedPercent"] as? NSNumber,
                  let minutes = value["windowDurationMins"] as? NSNumber,
                  let reset = value["resetsAt"] as? NSNumber,
                  used.doubleValue.isFinite, reset.doubleValue.isFinite,
                  minutes.doubleValue.isFinite, minutes.intValue > 0 else { return nil }
            return UsageWindow(usedPercent: used.doubleValue,
                               resetAt: Date(timeIntervalSince1970: reset.doubleValue),
                               windowMinutes: minutes.intValue)
        }
        let fiveHour = windows.first { $0.isFiveHourWindow }
        let weekly = windows.filter { $0.windowMinutes >= 6 * 24 * 60 }
            .max { $0.windowMinutes < $1.windowMinutes }
        guard let base = weekly ?? fiveHour else { return nil }
        return UsageSnapshot(usedPercent: base.usedPercent, resetAt: base.resetAt,
                             capturedAt: capturedAt, windowMinutes: base.windowMinutes,
                             source: "Codex 官方", shortWindow: fiveHour)
    }
}

// Only the installed Codex client handles authentication. No auth files or tokens
// are read, copied, logged, or sent through QuotaBar itself.
actor CodexUsageClient {
    private var connection: CodexUsageConnection?
    private var cached: UsageSnapshot?
    private var lastAttempt = Date.distantPast
    private let executable: URL?
    private let stateDirectory: URL
    private let timeout: TimeInterval

    init(executable: URL? = nil, stateDirectory: URL? = nil, timeout: TimeInterval = 12) {
        self.executable = executable ?? Self.findExecutable()
        self.stateDirectory = stateDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("QuotaBar/CodexRuntime", isDirectory: true)
        self.timeout = timeout
    }

    func latestUsage(force: Bool = false) throws -> UsageSnapshot {
        let elapsed = Date().timeIntervalSince(lastAttempt)
        let expired = cached?.fiveHourWindow.map { $0.resetAt <= Date() } ?? true
        let interval: TimeInterval = expired ? 15 : 60
        if !force && elapsed < interval {
            guard let cached else { throw UsageSyncError.unavailable }
            return cached
        }
        lastAttempt = Date()
        guard let executable else { throw UsageSyncError.notInstalled }
        do {
            if connection == nil {
                connection = try CodexUsageConnection(executable: executable, stateDirectory: stateDirectory,
                                                     timeout: timeout)
            }
            guard let connection else { throw UsageSyncError.unavailable }
            let response = try connection.request(method: "account/rateLimits/read")
            guard let value = CodexUsageResponse.snapshot(from: response) else {
                throw UsageSyncError.missingLimits
            }
            cached = value
            return value
        } catch {
            connection?.stop()
            connection = nil
            throw error as? UsageSyncError ?? .unavailable
        }
    }

    func stop() {
        connection?.stop()
        connection = nil
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let apps = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var candidates = apps.flatMap { directory in
            ["ChatGPT.app", "Codex.app"].flatMap { app in
                ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Contents/Resources/codex"]
                    .map { directory.appendingPathComponent(app).appendingPathComponent($0) }
            }
        }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map { URL(fileURLWithPath: $0) }
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class CodexUsageConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var requestID = 0
    private let timeout: TimeInterval

    init(executable: URL, stateDirectory: URL, timeout: TimeInterval) throws {
        self.timeout = timeout
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        process.executableURL = executable
        // Keep the query client's SQLite and logs separate from Codex's state.
        // Authentication and config are still managed by the installed client.
        let path = String(data: try JSONSerialization.data(withJSONObject: stateDirectory.path,
                                                         options: [.fragmentsAllowed]), encoding: .utf8)!
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "sqlite_home=" + path,
                             "-c", "log_dir=" + path]
        process.currentDirectoryURL = stateDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            _ = try request(method: "initialize", params: [
                "clientInfo": ["name": "quotabar", "title": "QuotaBar", "version": "1.0.2"]
            ])
            try send(["method": "initialized", "params": [:]])
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func request(method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        guard process.isRunning else { throw UsageSyncError.unavailable }
        requestID += 1
        var message: [String: Any] = ["id": requestID, "method": method]
        if let params { message["params"] = params }
        try send(message)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if Task.isCancelled { throw CancellationError() }
            while let newline = buffer.firstIndex(of: 10) {
                let data = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (response["id"] as? NSNumber)?.intValue == requestID else { continue }
                if let error = response["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    if text.contains("auth") || text.contains("login") || text.contains("sign in") {
                        throw UsageSyncError.notAuthenticated
                    }
                    throw UsageSyncError.unavailable
                }
                guard let result = response["result"] as? [String: Any] else {
                    throw UsageSyncError.missingLimits
                }
                return result
            }
            var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&fd, 1, 200)
            if ready < 0 { throw UsageSyncError.unavailable }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = Darwin.read(fd.fd, &bytes, bytes.count)
            guard count > 0 else { throw UsageSyncError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 2 * 1024 * 1024 else { throw UsageSyncError.unavailable }
        }
        throw UsageSyncError.timedOut
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + 0.3
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? output.fileHandleForReading.close()
    }
}
