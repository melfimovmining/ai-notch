import SwiftUI

/// The JSON Claude Code hands to a `statusLine` command, as far as SideNotch
/// cares about it. Decoded with `.convertFromSnakeCase`.
///
/// Every field is optional on purpose: `rateLimits` only appears for Claude.ai
/// Pro/Max accounts and only after the session's first API response, each
/// window disappears once it resets, and `contextWindow` values are null before
/// the first call and right after `/compact`.
struct StatusLinePayload: Decodable {
    struct Model: Decodable {
        var displayName: String?
    }

    struct Cost: Decodable {
        var totalCostUsd: Double?
    }

    struct ContextWindow: Decodable {
        var totalInputTokens: Int?
        var totalOutputTokens: Int?
        var contextWindowSize: Int?
        var usedPercentage: Double?
    }

    struct Window: Decodable {
        var usedPercentage: Double?
        /// Unix epoch seconds.
        var resetsAt: Double?
    }

    struct RateLimits: Decodable {
        var fiveHour: Window?
        var sevenDay: Window?
    }

    var sessionId: String?
    var model: Model?
    var cost: Cost?
    var contextWindow: ContextWindow?
    var rateLimits: RateLimits?

    static func decode(_ data: Data) throws -> StatusLinePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StatusLinePayload.self, from: data)
    }
}

/// Turns a status line payload into the three rings.
enum UsageMapper {
    static func metrics(from payload: StatusLinePayload, now: Date = Date()) -> [Metric] {
        let five = payload.rateLimits?.fiveHour
        let seven = payload.rateLimits?.sevenDay
        let context = payload.contextWindow

        let fiveValue = fraction(five?.usedPercentage)
        let sevenValue = fraction(seven?.usedPercentage)
        let contextValue = fraction(context?.usedPercentage)

        let sessionRow = UsageRow(
            id: "session",
            label: "Current session",
            meta: resetText(five?.resetsAt, now: now),
            value: fiveValue,
            tint: .notchOrange,
            captionOverride: five == nil ? "Waiting for data" : nil
        )
        let weekRow = UsageRow(
            id: "all",
            label: "All models",
            meta: resetText(seven?.resetsAt, now: now),
            value: sevenValue,
            tint: .notchGreen,
            captionOverride: seven == nil ? "Waiting for data" : nil
        )
        let contextRow = UsageRow(
            id: "context",
            label: "Context",
            meta: tokenText(context),
            value: contextValue,
            tint: .notchYellow,
            captionOverride: context?.usedPercentage == nil ? "Waiting for data" : nil
        )

        return [
            Metric(id: "five_hour", symbol: "sparkle", tint: .notchOrange,
                   value: fiveValue, title: "Claude Usage",
                   rows: [sessionRow, weekRow]),
            Metric(id: "seven_day", symbol: "calendar", tint: .notchGreen,
                   value: sevenValue, title: "Weekly Usage",
                   rows: [weekRow, sessionRow]),
            Metric(id: "context", symbol: "snowflake", tint: .notchYellow,
                   value: contextValue, title: contextTitle(payload),
                   rows: [contextRow, sessionRow])
        ]
    }

    private static func fraction(_ percentage: Double?) -> Double {
        guard let percentage else { return 0 }
        return min(max(percentage / 100, 0), 1)
    }

    private static func contextTitle(_ payload: StatusLinePayload) -> String {
        let name = payload.model?.displayName ?? "Context"
        guard let cost = payload.cost?.totalCostUsd, cost > 0 else { return name }
        return String(format: "%@ · $%.2f", name, cost)
    }

    /// "Resets in 51 min", "Resets in 2h 30m", or "Resets Thu 12:00 AM".
    static func resetText(_ epoch: Double?, now: Date) -> String {
        guard let epoch else { return "No window open" }
        let date = Date(timeIntervalSince1970: epoch)
        let seconds = date.timeIntervalSince(now)

        if seconds <= 0 { return "Resetting…" }
        if seconds < 3600 {
            return "Resets in \(Int((seconds / 60).rounded(.up))) min"
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds - Double(hours) * 3600) / 60)
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return "Resets \(formatter.string(from: date))"
    }

    /// "156k / 1M".
    static func tokenText(_ context: StatusLinePayload.ContextWindow?) -> String {
        guard let context,
              let used = context.totalInputTokens,
              let size = context.contextWindowSize else { return "—" }
        return "\(compact(used)) / \(compact(size))"
    }

    private static func compact(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...:
            let millions = Double(tokens) / 1_000_000
            return millions == millions.rounded()
                ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        case 1_000...:
            return "\(tokens / 1_000)k"
        default:
            return "\(tokens)"
        }
    }
}
