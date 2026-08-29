import Foundation
import SwiftUI

/// Checks the arithmetic behind the spend ring against the exact response
/// shapes the Admin API documents.
///
/// The interesting part is `amount`: it is a decimal *string* denominated in
/// cents, so "123.45" is $1.2345 — a plain `Double(amount)` read as dollars
/// would overstate the bill by 100x.
@main
struct CostMapperTests {
    static var failures = 0

    static func check(_ label: String, _ actual: String, _ expected: String) {
        if actual == expected {
            print("  PASS \(label): \(actual)")
        } else {
            print("  FAIL \(label): got \(actual), expected \(expected)")
            failures += 1
        }
    }

    static func main() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Two days of spend. Day two is "today" for the purposes of the test.
        let today = ISO8601DateFormatter().string(from: Date())
        let costJSON = """
        {"data":[
          {"starting_at":"2026-08-01T00:00:00Z","ending_at":"2026-08-02T00:00:00Z",
           "results":[
             {"amount":"123.45","currency":"USD","cost_type":"tokens",
              "description":"Claude Opus 5 Usage - Input Tokens","model":"claude-opus-5"},
             {"amount":"2000","currency":"USD","cost_type":"tokens",
              "description":"Claude Sonnet 5 Usage - Output Tokens","model":"claude-sonnet-5"}]},
          {"starting_at":"\(today)","ending_at":"\(today)",
           "results":[
             {"amount":"500.5","currency":"USD","cost_type":"tokens",
              "description":"Claude Opus 5 Usage - Output Tokens","model":"claude-opus-5"}]}],
         "has_more":false,"next_page":null}
        """
        let usageJSON = """
        {"data":[
          {"starting_at":"2026-08-01T00:00:00Z","ending_at":"2026-08-02T00:00:00Z",
           "results":[
             {"uncached_input_tokens":1500,"cache_read_input_tokens":200,
              "output_tokens":500,"model":"claude-opus-5",
              "cache_creation":{"ephemeral_1h_input_tokens":1000,
                                "ephemeral_5m_input_tokens":500},
              "server_tool_use":{"web_search_requests":10}}]}],
         "has_more":false,"next_page":null}
        """

        guard let cost = try? decoder.decode(CostReport.self, from: Data(costJSON.utf8)),
              let usage = try? decoder.decode(UsageReport.self, from: Data(usageJSON.utf8))
        else {
            print("  FAIL could not decode the documented response shapes")
            exit(1)
        }

        print("decoding:")
        check("cache_creation survives the digit-bearing key",
              "\(usage.data[0].results[0].cacheCreation.ephemeral1hInputTokens)", "1000")
        check("tokens are summed across every bucket",
              "\(usage.data[0].results[0].totalTokens)", "3700")

        // 123.45 + 2000 + 500.5 = 2623.95 cents = $26.2395 -> "$26.24"
        let anchor = Date(timeIntervalSince1970: 1_756_425_600)  // 2025-08-29 UTC
        let metric = CostMapper.metric(cost: cost, usage: usage,
                                       since: anchor, balance: 35.10)
        print("balance countdown:")
        // $35.10 - $26.2395 = $8.8605 -> "$8.86"; 8.8605/35.10 = 25.2% -> 25%
        check("remaining", metric.rows[0].caption, "$8.86 left · 25%")
        check("ring drains rather than fills", metric.percentText, "25%")
        check("spend row names the anchor date and top model",
              metric.rows[1].caption, "$26.24 · Top: Sonnet 5")
        check("token summary", metric.rows[1].meta, "3k tokens")

        // Spending past the recorded balance means credits were bought; the API
        // exposes no top-up, so the ring must say so rather than go negative.
        let overspent = CostMapper.metric(cost: cost, usage: usage,
                                          since: anchor, balance: 10)
        print("stale anchor:")
        check("never negative", overspent.percentText, "0%")
        check("prompts for a new balance", overspent.rows[0].label, "Out of credit")

        // No balance recorded yet: spend still shows, ring stays empty.
        let unanchored = CostMapper.metric(cost: cost, usage: usage,
                                           since: anchor, balance: nil)
        print("no anchor:")
        check("falls back to spend", unanchored.title, "API Spend")
        check("still reports the figure", unanchored.rows[0].caption, "$26.24 · Top: Sonnet 5")

        print("formatting:")
        check("model id is prettified", CostMapper.prettyModel("claude-opus-5"), "Opus 5")
        check("dotted versions survive", CostMapper.prettyModel("claude-haiku-4-5"), "Haiku 4 5")
        check("sub-cent spend keeps its digits", CostMapper.money(0.0042), "$0.0042")
        check("zero tokens reads as prose", CostMapper.tokenText(0), "No tokens yet")
        check("millions are abbreviated", CostMapper.tokenText(2_400_000), "2.4M tokens")

        // Colour thresholds are what make a nearly-empty wallet obvious.
        print("thresholds:")
        check("plenty left is green", "\(CostMapper.tint(forRemaining: 0.8))",
              "\(Color.notchGreen)")
        check("getting low is yellow", "\(CostMapper.tint(forRemaining: 0.2))",
              "\(Color.notchYellow)")
        check("nearly empty is orange", "\(CostMapper.tint(forRemaining: 0.05))",
              "\(Color.notchOrange)")

        exit(failures == 0 ? 0 : 1)
    }
}
