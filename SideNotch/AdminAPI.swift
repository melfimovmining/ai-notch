import Foundation

/// The two Anthropic Admin API reports the cost ring is built from.
///
/// These endpoints are deliberately absent from every Anthropic SDK (they are
/// documented as raw-HTTP only), and there is no Swift SDK regardless, so this
/// speaks the REST API directly with URLSession.
///
/// Both require an *admin* credential — an Admin API key (`sk-ant-admin01-…`),
/// an `org:admin` OAuth token, or a personal key that is not scoped to a
/// workspace. An ordinary workspace-scoped key is rejected with 401, and the
/// Admin API is unavailable to individual (non-organization) accounts, so a
/// perfectly valid Messages-API key can still fail here. `AdminAPIError`
/// distinguishes those cases so the UI can say which one happened.
enum AdminAPI {
    static let base = URL(string: "https://api.anthropic.com/v1/organizations")!
    static let version = "2023-06-01"

    /// Anthropic asks integrations to identify themselves.
    static let userAgent = "AINotch/1.0 (https://github.com/melfimovmining/ai-notch)"

    // MARK: - Cost report

    /// `GET /v1/organizations/cost_report`
    ///
    /// Grouped by `description` so each row carries the model and cost type;
    /// that is the only way to attribute spend to a specific model.
    /// Pages until the report is exhausted: a single request caps at 31 daily
    /// buckets, and the balance anchor can easily be older than that.
    static func costReport(key: String,
                           from start: Date,
                           to end: Date,
                           session: URLSession = .shared) async throws -> CostReport {
        var buckets: [CostReport.Bucket] = []
        var page: String?

        repeat {
            var items = [
                URLQueryItem(name: "starting_at", value: rfc3339(start)),
                URLQueryItem(name: "ending_at", value: rfc3339(end)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31"),
                URLQueryItem(name: "group_by[]", value: "description")
            ]
            if let page { items.append(URLQueryItem(name: "page", value: page)) }

            let response: CostReport = try await get(path: "cost_report", query: items,
                                                     key: key, session: session)
            buckets += response.data
            page = response.hasMore ? response.nextPage : nil
        } while page != nil && buckets.count < maxBuckets

        return CostReport(data: buckets, hasMore: false, nextPage: nil)
    }

    /// A year of daily buckets is far more than the rings need, and stops a
    /// malformed cursor from looping forever.
    private static let maxBuckets = 400

    // MARK: - Usage report

    /// `GET /v1/organizations/usage_report/messages`
    static func usageReport(key: String,
                            from start: Date,
                            to end: Date,
                            session: URLSession = .shared) async throws -> UsageReport {
        var buckets: [UsageReport.Bucket] = []
        var page: String?

        repeat {
            var items = [
                URLQueryItem(name: "starting_at", value: rfc3339(start)),
                URLQueryItem(name: "ending_at", value: rfc3339(end)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31")
            ]
            if let page { items.append(URLQueryItem(name: "page", value: page)) }

            let response: UsageReport = try await get(path: "usage_report/messages", query: items,
                                                      key: key, session: session)
            buckets += response.data
            page = response.hasMore ? response.nextPage : nil
        } while page != nil && buckets.count < maxBuckets

        return UsageReport(data: buckets, hasMore: false, nextPage: nil)
    }

    // MARK: - Transport

    private static func get<T: Decodable>(path: String,
                                          query: [URLQueryItem],
                                          key: String,
                                          session: URLSession) async throws -> T {
        var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AdminAPIError.transport("No HTTP response")
        }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw AdminAPIError.unauthorized(Self.message(from: data))
        case 404:
            // The Admin API is not enabled for individual accounts; the org
            // routes simply are not there.
            throw AdminAPIError.notAnOrganization(Self.message(from: data))
        case 429:
            throw AdminAPIError.rateLimited
        default:
            throw AdminAPIError.http(http.statusCode, Self.message(from: data))
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AdminAPIError.decoding(String(describing: error))
        }
    }

    /// Pulls `error.message` out of an Anthropic error body, when there is one.
    private static func message(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Failure: Decodable { let message: String? }
            let error: Failure?
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let message = envelope.error?.message {
            return message
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum AdminAPIError: Error {
    case unauthorized(String)
    case notAnOrganization(String)
    case rateLimited
    case http(Int, String)
    case decoding(String)
    case transport(String)

    /// Short enough for a hover card row.
    var shortDescription: String {
        switch self {
        case .unauthorized:
            return "Key rejected — needs admin"
        case .notAnOrganization:
            return "No org on this account"
        case .rateLimited:
            return "Rate limited"
        case .http(let code, _):
            return "HTTP \(code)"
        case .decoding:
            return "Bad response"
        case .transport:
            return "Offline"
        }
    }

    /// The full story, for the alert shown when the user sets a key.
    var longDescription: String {
        switch self {
        case .unauthorized(let message):
            return """
            The API rejected this key for the Admin API.

            Usage and cost reports need an Admin API key (sk-ant-admin01-…), an \
            org:admin OAuth token, or a personal key that is not scoped to a \
            workspace. An ordinary workspace-scoped key will not work here even \
            though it works fine for sending messages.

            \(message)
            """
        case .notAnOrganization(let message):
            return """
            This account does not appear to have an organization.

            The Admin API — and so the usage and cost reports — is unavailable \
            for individual accounts. You can create an organization in the \
            Claude Console under Settings → Organization.

            \(message)
            """
        case .rateLimited:
            return "Rate limited by the API. AI Notch polls once a minute; try again shortly."
        case .http(let code, let message):
            return "The API returned HTTP \(code).\n\n\(message)"
        case .decoding(let detail):
            return "Could not read the API response.\n\n\(detail)"
        case .transport(let detail):
            return "Could not reach api.anthropic.com.\n\n\(detail)"
        }
    }
}

// MARK: - Cost report shapes

/// Response of `GET /v1/organizations/cost_report`.
struct CostReport: Decodable {
    let data: [Bucket]
    let hasMore: Bool
    let nextPage: String?

    init(data: [Bucket], hasMore: Bool, nextPage: String?) {
        self.data = data
        self.hasMore = hasMore
        self.nextPage = nextPage
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }

    struct Bucket: Decodable {
        let startingAt: Date
        let endingAt: Date
        let results: [Entry]

        enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct Entry: Decodable {
        /// Cost in the currency's *lowest units* — cents — as a decimal string.
        /// `"123.45"` means $1.2345. Kept as `Decimal` so summing many small
        /// rows does not drift the way `Double` would.
        let amount: Decimal
        let currency: String
        let description: String?
        let model: String?
        let costType: String?

        enum CodingKeys: String, CodingKey {
            case amount, currency, description, model
            case costType = "cost_type"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try container.decode(String.self, forKey: .amount)
            amount = Decimal(string: raw) ?? 0
            currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
            description = try container.decodeIfPresent(String.self, forKey: .description)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            costType = try container.decodeIfPresent(String.self, forKey: .costType)
        }
    }
}

// MARK: - Usage report shapes

/// Response of `GET /v1/organizations/usage_report/messages`.
///
/// Spelled with explicit keys rather than `.convertFromSnakeCase`: that
/// strategy would have to turn `ephemeral_1h_input_tokens` into
/// `ephemeral1hInputTokens`, and capitalising a leading digit is a no-op, so
/// the mapping is too subtle to rely on.
struct UsageReport: Decodable {
    let data: [Bucket]
    let hasMore: Bool
    let nextPage: String?

    init(data: [Bucket], hasMore: Bool, nextPage: String?) {
        self.data = data
        self.hasMore = hasMore
        self.nextPage = nextPage
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }

    struct Bucket: Decodable {
        let startingAt: Date
        let endingAt: Date
        let results: [Entry]

        enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct Entry: Decodable {
        let model: String?
        let uncachedInputTokens: Int
        let cacheReadInputTokens: Int
        let outputTokens: Int
        let cacheCreation: CacheCreation

        /// Every token this row was billed for, cache traffic included.
        var totalTokens: Int {
            uncachedInputTokens + cacheReadInputTokens + outputTokens
                + cacheCreation.ephemeral1hInputTokens
                + cacheCreation.ephemeral5mInputTokens
        }

        var inputTokens: Int {
            uncachedInputTokens + cacheReadInputTokens
                + cacheCreation.ephemeral1hInputTokens
                + cacheCreation.ephemeral5mInputTokens
        }

        enum CodingKeys: String, CodingKey {
            case model
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreation = "cache_creation"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            uncachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .uncachedInputTokens) ?? 0
            cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
            outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            cacheCreation = try container.decodeIfPresent(CacheCreation.self, forKey: .cacheCreation)
                ?? CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0)
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral1hInputTokens: Int
        let ephemeral5mInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        }

        init(ephemeral1hInputTokens: Int, ephemeral5mInputTokens: Int) {
            self.ephemeral1hInputTokens = ephemeral1hInputTokens
            self.ephemeral5mInputTokens = ephemeral5mInputTokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ephemeral1hInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral1hInputTokens) ?? 0
            ephemeral5mInputTokens = try container.decodeIfPresent(Int.self, forKey: .ephemeral5mInputTokens) ?? 0
        }
    }
}
