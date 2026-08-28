import Foundation
import Observation

/// Watches `~/.sidenotch/sessions/` for the JSON blobs written by
/// `scripts/statusline-sidenotch.sh` and republishes them as ring metrics.
///
/// The newest file wins: the 5-hour and 7-day windows are account-wide so every
/// session agrees on them, and the context/cost figures should come from
/// whichever Claude Code session spoke last.
@Observable
final class UsageMonitor {
    private(set) var metrics: [Metric] = Metric.samples
    /// False while we are still showing the placeholder numbers.
    private(set) var isLive = false

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var timer: Timer?

    static var defaultDirectory: URL {
        let base = ProcessInfo.processInfo.environment["SIDENOTCH_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".sidenotch")
        return base.appendingPathComponent("sessions")
    }

    init(directory: URL = UsageMonitor.defaultDirectory) {
        self.directory = directory
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        watchDirectory()

        // The countdowns ("Resets in 51 min") have to keep ticking even when no
        // new file lands.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.reload()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func watchDirectory() {
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    private func reload() {
        guard let payload = newestPayload() else {
            metrics = Metric.samples
            isLive = false
            return
        }
        metrics = UsageMapper.metrics(from: payload)
        isLive = true
    }

    /// Most recently modified session file that still parses.
    private func newestPayload() -> StatusLinePayload? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let candidates = files
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return l > r
            }

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let payload = try? StatusLinePayload.decode(data) {
                return payload
            }
        }
        return nil
    }
}
