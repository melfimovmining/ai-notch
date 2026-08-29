import Foundation
import Observation
import SwiftUI

/// Polls the Admin API and republishes remaining API credit as the fourth ring.
///
/// Separate from `UsageMonitor` on purpose: that one reads local files written
/// by a Claude Code status line and is always available, while this one talks
/// to the network, needs a credential the user has to supply, and can fail in
/// ways worth showing. Keeping them apart means a broken or absent API key
/// never disturbs the three rings that work offline.
@Observable
final class CostMonitor {
    /// Nil whenever there is no ring to show — no key set, or the first poll
    /// has not resolved yet. The notch simply renders three rings then.
    private(set) var metric: Metric?
    private(set) var lastError: AdminAPIError?

    /// Fired when the ring appears or disappears, so the panel can resize: the
    /// bar's height is a function of how many rings it holds.
    @ObservationIgnored var onRingCountChange: (() -> Void)?

    /// The API accepts sustained polling at once a minute, and the data itself
    /// only settles within about five minutes of a request, so there is nothing
    /// to gain from going faster.
    private static let interval: TimeInterval = 60

    private var timer: Timer?
    private var inFlight: Task<Void, Never>?

    deinit {
        timer?.invalidate()
        inFlight?.cancel()
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Called by the menu after the key or the balance changes.
    func refresh() {
        guard let key = AdminCredentials.key else {
            publish(nil)
            lastError = nil
            return
        }

        inFlight?.cancel()
        inFlight = Task { [weak self] in
            await self?.poll(key: key)
        }
    }

    private func poll(key: String) async {
        let start = Self.windowStart(anchor: AdminCredentials.balanceAnchor)

        do {
            // Two independent reports; no reason to wait for one before the other.
            async let costs = AdminAPI.costReport(key: key, from: start, to: Date())
            async let usage = AdminAPI.usageReport(key: key, from: start, to: Date())
            let (cost, used) = try await (costs, usage)

            guard !Task.isCancelled else { return }
            publish(CostMapper.metric(cost: cost, usage: used, since: start))
            lastError = nil
        } catch let error as AdminAPIError {
            guard !Task.isCancelled else { return }
            lastError = error
            publish(CostMapper.failed(error))
        } catch {
            guard !Task.isCancelled else { return }
            let wrapped = AdminAPIError.transport(error.localizedDescription)
            lastError = wrapped
            publish(CostMapper.failed(wrapped))
        }
    }

    private func publish(_ new: Metric?) {
        let had = metric != nil
        metric = new
        if had != (new != nil) { onRingCountChange?() }
    }

    /// Where the spend window starts.
    ///
    /// From the anchor's own UTC day when a balance has been recorded — the
    /// reports bucket by UTC day, so a mid-day anchor cannot be split any finer
    /// than that. Counting the whole day errs towards *over*-counting spend,
    /// which understates the remaining balance rather than overstating it.
    ///
    /// With no anchor, falls back to the start of the current UTC month so the
    /// card can still show what has been spent.
    static func windowStart(anchor: Date?, now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        if let anchor {
            return calendar.startOfDay(for: anchor)
        }
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }
}

// MARK: - Mapping

/// Turns the two reports into the balance ring.
enum CostMapper {
    static func metric(cost: CostReport,
                       usage: UsageReport,
                       since start: Date,
                       balance: Double? = AdminCredentials.creditBalance) -> Metric {
        let spent = dollars(in: cost.data.flatMap(\.results))
        let tokens = usage.data.flatMap(\.results).reduce(0) { $0 + $1.totalTokens }
        let leader = topModel(cost)

        guard let balance, balance > 0 else {
            return unanchored(spent: spent, tokens: tokens, leader: leader)
        }

        let remaining = Decimal(balance) - spent
        let spentRow = UsageRow(
            id: "spent",
            label: "Spent since \(shortDate(start))",
            meta: tokenText(tokens),
            value: 0,
            tint: .notchOrange,
            captionOverride: leader.map { "\(money(spent)) · Top: \($0)" } ?? money(spent)
        )

        // Spending past the recorded balance means the anchor is stale — almost
        // always because credits were bought. Nothing in the API exposes a
        // top-up, so the app says so rather than showing a negative balance.
        guard remaining > 0 else {
            return Metric(
                id: "spend", symbol: "creditcard", tint: .notchOrange,
                value: 0, title: "API Balance",
                rows: [
                    UsageRow(id: "remaining", label: "Out of credit",
                             meta: "of \(money(balance)) recorded",
                             value: 0, tint: .notchOrange,
                             captionOverride: "Bought more? Right-click → Set Credit Balance"),
                    spentRow
                ])
        }

        // The ring drains: full is a full wallet, empty is an empty one.
        let left = NSDecimalNumber(decimal: remaining).doubleValue
        let fraction = min(max(left / balance, 0), 1)
        let colour = tint(forRemaining: fraction)

        return Metric(
            id: "spend",
            symbol: "creditcard",
            tint: colour,
            value: fraction,
            title: "API Balance",
            rows: [
                UsageRow(id: "remaining", label: "Remaining",
                         meta: "of \(money(balance)) recorded",
                         value: fraction, tint: colour,
                         captionOverride: "\(money(remaining)) left · \(Metric.percent(fraction))"),
                spentRow
            ])
    }

    /// A key works, but no balance has been recorded yet — show the spend that
    /// is available and point at the setting that turns it into a balance.
    private static func unanchored(spent: Decimal, tokens: Int, leader: String?) -> Metric {
        Metric(id: "spend", symbol: "creditcard", tint: .notchBlue,
               value: 0, title: "API Spend",
               rows: [
                UsageRow(id: "remaining", label: "This month",
                         meta: tokenText(tokens), value: 0, tint: .notchBlue,
                         captionOverride: leader.map { "\(money(spent)) · Top: \($0)" }
                            ?? money(spent)),
                UsageRow(id: "spent", label: "For a balance ring",
                         meta: "one-time setup", value: 0, tint: .notchOrange,
                         captionOverride: "Right-click → Set Credit Balance")
               ])
    }

    static func failed(_ error: AdminAPIError) -> Metric {
        Metric(id: "spend", symbol: "creditcard", tint: .notchBlue,
               value: 0, title: "API Balance",
               rows: [
                UsageRow(id: "remaining", label: "Balance", meta: "Unavailable",
                         value: 0, tint: .notchBlue,
                         captionOverride: error.shortDescription),
                UsageRow(id: "spent", label: "Retrying", meta: "every 60s",
                         value: 0, tint: .notchOrange,
                         captionOverride: "Right-click the tab to change the key")
               ])
    }

    /// Green with plenty left, yellow when it is getting low, orange near empty.
    static func tint(forRemaining fraction: Double) -> Color {
        switch fraction {
        case ..<0.10: return .notchOrange
        case ..<0.25: return .notchYellow
        default: return .notchGreen
        }
    }

    // MARK: - Arithmetic

    /// `amount` arrives in cents as a decimal string. Stays `Decimal` the whole
    /// way: converting to `Double` before rounding loses half-cent figures —
    /// $5.005 is not representable in binary and truncates to $5.00.
    private static func dollars(in entries: [CostReport.Entry]) -> Decimal {
        entries.reduce(Decimal(0)) { $0 + $1.amount } / 100
    }

    /// Model with the highest spend in the window, prettified for display.
    private static func topModel(_ report: CostReport) -> String? {
        var totals: [String: Decimal] = [:]
        for entry in report.data.flatMap(\.results) {
            guard let model = entry.model else { continue }
            totals[model, default: 0] += entry.amount
        }
        guard let winner = totals.max(by: { $0.value < $1.value })?.key else { return nil }
        return prettyModel(winner)
    }

    /// "claude-opus-5" → "Opus 5".
    static func prettyModel(_ id: String) -> String {
        let trimmed = id.hasPrefix("claude-") ? String(id.dropFirst("claude-".count)) : id
        return trimmed
            .split(separator: "-")
            .map { part in
                // A bare family name gets capitalised; version fragments stay
                // numeric.
                part.allSatisfy(\.isNumber) ? String(part) : part.capitalized
            }
            .joined(separator: " ")
    }

    // MARK: - Formatting

    /// "$31.04", or "$0.0042" when the figure would otherwise round to zero.
    static func money(_ amount: Decimal) -> String {
        // Sub-cent spend is real on cheap models; showing "$0.00" would read as
        // "nothing happened".
        if amount > 0 && amount < Decimal(string: "0.01")! {
            return "$" + rounded(amount, places: 4)
        }
        return "$" + rounded(amount, places: 2)
    }

    static func money(_ amount: Double) -> String { money(Decimal(amount)) }

    /// Half-up rounding in decimal, then a fixed number of places.
    private static func rounded(_ value: Decimal, places: Int) -> String {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, places, .plain)

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ""
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        return formatter.string(from: NSDecimalNumber(decimal: result)) ?? "0"
    }

    /// "1.2M tokens".
    static func tokenText(_ tokens: Int) -> String {
        switch tokens {
        case 0:
            return "No tokens yet"
        case 1_000_000...:
            return String(format: "%.1fM tokens", Double(tokens) / 1_000_000)
        case 1_000...:
            return "\(tokens / 1_000)k tokens"
        default:
            return "\(tokens) tokens"
        }
    }

    /// "Aug 29", in UTC to match the report buckets.
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}
