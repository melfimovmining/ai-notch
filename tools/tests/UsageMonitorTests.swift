import Foundation

/// Verifies that UsageMonitor notices a session file written the way
/// scripts/statusline-sidenotch.sh writes it (temp file + atomic rename).
@main
struct UsageMonitorTests {
    static func main() {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        let monitor = UsageMonitor(directory: dir)
        monitor.start()
        print("before any file -> isLive=\(monitor.isLive) ring0=\(monitor.metrics[0].percentText) (placeholder)")

        let now = Date().timeIntervalSince1970
        let json = """
        {"session_id":"live","model":{"display_name":"Opus"},
         "cost":{"total_cost_usd":1.25},
         "context_window":{"total_input_tokens":420000,"context_window_size":1000000,"used_percentage":42},
         "rate_limits":{"five_hour":{"used_percentage":88.4,"resets_at":\(now + 900)},
                        "seven_day":{"used_percentage":31.0,"resets_at":\(now + 300000)}}}
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tmp = dir.appendingPathComponent(".tmp-write")
            try? json.write(to: tmp, atomically: false, encoding: .utf8)
            // Atomic rename, exactly like the shell script does.
            try? FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent("live.json"))
            print("wrote live.json")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        print("after write   -> isLive=\(monitor.isLive) " +
              monitor.metrics.map { "\($0.id)=\($0.percentText)" }.joined(separator: " "))
        print("card title    -> \(monitor.metrics[2].title)")
        print("session meta  -> \(monitor.metrics[0].rows[0].meta)")
        exit(monitor.isLive && monitor.metrics[0].percentText == "88%" ? 0 : 1)
    }
}
