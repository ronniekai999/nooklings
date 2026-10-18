import Foundation

struct ModelCapabilities {
    var images = false
    var webSearch = false
    var adaptiveThinking = false
    var efforts: [String] = []
}

struct ModelPrice {
    let input: Double
    let output: Double
    var cacheReadMultiplier = 0.1
    var longContextThreshold: Int? = nil
    var longContextMultiplier = 1.0

    func cost(_ usage: AnthropicUsage) -> Double {
        let totalInput = usage.inputTokens + usage.cacheReadTokens + usage.cacheWriteTokens
        let multiplier = longContextThreshold.map { totalInput > $0 ? longContextMultiplier : 1 } ?? 1
        let writes5m = max(0, usage.cacheWriteTokens - usage.cacheWrite1hTokens)
        let inputUnits = Double(usage.inputTokens) + Double(usage.cacheReadTokens) * cacheReadMultiplier
            + Double(writes5m) * 1.25 + Double(usage.cacheWrite1hTokens) * 2
        return (inputUnits * input + Double(usage.outputTokens) * output) / 1_000_000 * multiplier
            + Double(usage.searches) * 0.01
    }
}

struct ModelMetadata: Identifiable {
    let id: String
    var name: String
    var capabilities = ModelCapabilities()
    var maxInputTokens: Int? = nil
    var maxOutputTokens: Int? = nil
    var price: ModelPrice? = nil
    var availabilityVerified = false
    var deprecated = false
}

enum ModelCatalog {
    static let verifiedOn = "2026-10-18"
    static let pricingURL = URL(string: "https://platform.claude.com/docs/en/about-claude/pricing")!
    static let verificationDate = ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z")!
    static func pricesAreStale(at date: Date) -> Bool { date.timeIntervalSince(verificationDate) > 90 * 86_400 }

    // The provider's live catalogue controls availability and capabilities.
    // This dated reference supplies documented fallback metadata and list prices.
    static let reference: [ModelMetadata] = [
        ModelMetadata(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6",
            capabilities: ModelCapabilities(images: true, webSearch: true, adaptiveThinking: true, efforts: ["low", "medium", "high"]),
            maxInputTokens: 1_000_000, maxOutputTokens: 64_000, price: ModelPrice(input: 3, output: 15)),
        ModelMetadata(id: "claude-opus-4-8", name: "Claude Opus 4.8",
            capabilities: ModelCapabilities(images: true, webSearch: true, adaptiveThinking: true, efforts: ["low", "medium", "high", "max"]),
            maxInputTokens: 1_000_000, maxOutputTokens: 128_000, price: ModelPrice(input: 5, output: 25)),
        ModelMetadata(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5",
            capabilities: ModelCapabilities(images: true, webSearch: true),
            maxInputTokens: 200_000, maxOutputTokens: 64_000, price: ModelPrice(input: 1, output: 5)),
        // Discover these models before enabling optional features: new capabilities
        // must come from the API, never be inferred from a model-name prefix.
        ModelMetadata(id: "claude-opus-5-5", name: "Claude Opus 5.5",
            price: ModelPrice(input: 4, output: 20, cacheReadMultiplier: 0.05)),
        ModelMetadata(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5",
            price: ModelPrice(input: 2, output: 10, cacheReadMultiplier: 0.05)),
        ModelMetadata(id: "claude-haiku-5-5", name: "Claude Haiku 5.5",
            price: ModelPrice(input: 0.1, output: 0.5, longContextThreshold: 100_000, longContextMultiplier: 5))
    ]

    static func metadata(for id: String) -> ModelMetadata {
        reference.first { $0.id == id } ?? ModelMetadata(id: id, name: id)
    }

    static func discover(key: String, session: URLSession) async throws -> [ModelMetadata] {
        var results: [ModelMetadata] = [], cursor: String?, visited = Set<String>()
        for _ in 0..<20 {
            var url = URLComponents(string: "https://api.anthropic.com/v1/models")!
            url.queryItems = [URLQueryItem(name: "limit", value: "100")]
            if let cursor { url.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 30
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ChatGPTConnectionError("Couldn't verify Claude models. Check your API key and retry Check availability.")
            }
            let page = try JSONDecoder().decode(AnthropicModelPage.self, from: data)
            results += page.data.filter { $0.lifecycle != "retired" }.map(\.metadata)
            if !page.has_more {
                var seen = Set<String>()
                return results.filter { seen.insert($0.id).inserted }
            }
            guard let next = page.last_id, visited.insert(next).inserted else { break }
            cursor = next
        }
        throw ChatGPTConnectionError("The model catalog was incomplete. Retry Check availability.")
    }
}

struct AnthropicModelPage: Decodable {
    let data: [AnthropicModelRecord]
    let has_more: Bool
    let last_id: String?
}

struct AnthropicModelRecord: Decodable {
    struct Feature: Decodable { let supported: Bool }
    struct Capabilities: Decodable {
        struct Thinking: Decodable { let types: [String: Feature]? }
        struct ServerTools: Decodable { let web_search: Feature? }
        struct Effort: Decodable {
            let low: Feature?, medium: Feature?, high: Feature?, xhigh: Feature?, max: Feature?
            var supported: [String] {
                [("low", low), ("medium", medium), ("high", high), ("xhigh", xhigh), ("max", max)]
                    .filter { $0.1?.supported == true }.map(\.0)
            }
        }
        let image_input: Feature?, thinking: Thinking?, server_tools: ServerTools?, effort: Effort?
    }
    let id: String
    let display_name: String
    let capabilities: Capabilities?
    let max_input_tokens: Int?
    let max_tokens: Int?
    let lifecycle: String?

    var metadata: ModelMetadata {
        var value = ModelCatalog.metadata(for: id)
        value.name = display_name
        if let c = capabilities {
            value.capabilities = ModelCapabilities(images: c.image_input?.supported == true,
                webSearch: c.server_tools?.web_search?.supported == true,
                adaptiveThinking: c.thinking?.types?["adaptive"]?.supported == true,
                efforts: c.effort?.supported ?? [])
        }
        if let n = max_input_tokens, n > 0 { value.maxInputTokens = n }
        if let n = max_tokens, n > 0 { value.maxOutputTokens = n }
        value.availabilityVerified = true; value.deprecated = lifecycle == "deprecated"
        return value
    }
}
