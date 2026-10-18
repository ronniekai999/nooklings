import Foundation

/// Snapshot these settings once per send so retries and billing use the same model.
struct AnthropicRequestConfiguration {
    let model: String
    let effort: String
    let webSearch: Bool
    let system: String
    var maxOutputTokens = 8192
    var maxSearches = 5
    var capabilities: ModelCapabilities? = nil

    static var visionModels: Set<String> { Set(ModelCatalog.reference.filter { $0.capabilities.images }.map(\.id)) }

    static func supportsAdaptiveThinking(_ model: String) -> Bool {
        ModelCatalog.metadata(for: model).capabilities.adaptiveThinking
    }

    func payload(messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model, "max_tokens": max(256, maxOutputTokens), "stream": true,
            "system": system, "messages": messages
        ]
        let features = capabilities ?? ModelCatalog.metadata(for: model).capabilities
        if features.adaptiveThinking {
            body["thinking"] = ["type": "adaptive"]
            if features.efforts.contains(effort) { body["output_config"] = ["effort": effort] }
        }
        if webSearch, features.webSearch, maxSearches > 0 {
            body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": min(10, maxSearches)]]
        }
        return body
    }
}

struct AnthropicUsage {
    var inputTokens = 0
    var outputTokens = 0
    var searches = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var cacheWrite1hTokens = 0

    /// Streaming usage fields are cumulative. The final input count can grow after a search.
    mutating func update(from usage: [String: Any]) {
        if let value = usage["input_tokens"] as? Int { inputTokens = value }
        if let value = usage["output_tokens"] as? Int { outputTokens = value }
        if let value = usage["cache_read_input_tokens"] as? Int { cacheReadTokens = max(0, value) }
        if let value = usage["cache_creation_input_tokens"] as? Int { cacheWriteTokens = max(0, value) }
        if let creation = usage["cache_creation"] as? [String: Any],
           let value = creation["ephemeral_1h_input_tokens"] as? Int { cacheWrite1hTokens = max(0, value) }
        if let tool = usage["server_tool_use"] as? [String: Any],
           let value = tool["web_search_requests"] as? Int { searches = value }
    }
}
