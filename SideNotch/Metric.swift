import SwiftUI

/// One ring in the notch, plus the card shown when it is hovered.
struct Metric: Identifiable {
    /// Stable across refreshes so SwiftUI keeps view identity (and the hover
    /// state) when new numbers arrive.
    let id: String
    /// SF Symbol placeholder for the service logo.
    let symbol: String
    let tint: Color
    /// 0...1
    let value: Double
    /// Card header, e.g. "Claude Usage".
    let title: String
    let rows: [UsageRow]

    var percentText: String { Self.percent(value) }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// One labelled progress bar inside the hover card.
struct UsageRow: Identifiable {
    let id: String
    /// Leading label, e.g. "Current session".
    let label: String
    /// Trailing secondary text, e.g. "Resets in 51 min".
    let meta: String
    /// 0...1
    let value: Double
    let tint: Color
    /// Replaces the default "73% Used" caption when set.
    var captionOverride: String?

    var caption: String { captionOverride ?? "\(Metric.percent(value)) Used" }
}

extension Color {
    static let notchOrange = Color(red: 1.00, green: 0.38, blue: 0.16)
    static let notchGreen = Color(red: 0.20, green: 0.90, blue: 0.44)
    static let notchYellow = Color(red: 0.92, green: 0.93, blue: 0.20)
}

extension Metric {
    /// Shown until a Claude Code session reports in — see `UsageMonitor`.
    static let samples: [Metric] = [
        Metric(
            id: "five_hour",
            symbol: "sparkle",
            tint: .notchOrange,
            value: 0.73,
            title: "Claude Usage",
            rows: [
                UsageRow(id: "session", label: "Current session",
                         meta: "Resets in 51 min", value: 0.73, tint: .notchOrange),
                UsageRow(id: "all", label: "All models",
                         meta: "Resets Thu 12:00 AM", value: 0.07, tint: .notchGreen)
            ]
        ),
        Metric(
            id: "seven_day",
            symbol: "calendar",
            tint: .notchGreen,
            value: 0.21,
            title: "Weekly Usage",
            rows: [
                UsageRow(id: "all", label: "All models",
                         meta: "Resets Thu 12:00 AM", value: 0.21, tint: .notchGreen),
                UsageRow(id: "session", label: "Current session",
                         meta: "Resets in 51 min", value: 0.73, tint: .notchOrange)
            ]
        ),
        Metric(
            id: "context",
            symbol: "snowflake",
            tint: .notchYellow,
            value: 0.52,
            title: "Context Window",
            rows: [
                UsageRow(id: "context", label: "Context",
                         meta: "104k / 200k", value: 0.52, tint: .notchYellow),
                UsageRow(id: "session", label: "Current session",
                         meta: "Resets in 51 min", value: 0.73, tint: .notchOrange)
            ]
        )
    ]
}
