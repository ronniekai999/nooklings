import XCTest
@testable import Byte

final class ModelCatalogTests: XCTestCase {
    func testLiveCapabilitiesOverrideReferenceAndUnknownModelsStayUnpriced() throws {
        let data = Data(#"{"data":[{"id":"claude-sonnet-4-6","display_name":"Sonnet","capabilities":{"image_input":{"supported":false},"server_tools":{"web_search":{"supported":false}},"thinking":{"types":{"adaptive":{"supported":false}}}},"max_input_tokens":12000,"max_tokens":1000},{"id":"future-model","display_name":"Future","capabilities":{"image_input":{"supported":true}}}],"has_more":false}"#.utf8)
        let page = try JSONDecoder().decode(AnthropicModelPage.self, from: data)
        let sonnet = page.data[0].metadata, future = page.data[1].metadata
        XCTAssertFalse(sonnet.capabilities.images)
        XCTAssertFalse(sonnet.capabilities.adaptiveThinking)
        XCTAssertEqual(sonnet.maxInputTokens, 12_000)
        let body = AnthropicRequestConfiguration(model: sonnet.id, effort: "high", webSearch: true, system: "test",
            maxOutputTokens: 512, maxSearches: 2, capabilities: sonnet.capabilities).payload(messages: [])
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["tools"])
        XCTAssertEqual(body["max_tokens"] as? Int, 512)
        XCTAssertTrue(future.capabilities.images)
        XCTAssertFalse(future.capabilities.webSearch)
        XCTAssertNil(future.price)
        XCTAssertTrue(future.availabilityVerified)
    }

    func testDatedPricesIncludeCacheTiersAndCorrectedOpusRate() throws {
        let opus = try XCTUnwrap(ModelCatalog.metadata(for: "claude-opus-4-8").price)
        XCTAssertEqual(opus.cost(AnthropicUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)), 30)
        var usage = AnthropicUsage()
        usage.update(from: ["input_tokens": 100, "output_tokens": 10, "cache_read_input_tokens": 1000,
                            "cache_creation_input_tokens": 200, "cache_creation": ["ephemeral_1h_input_tokens": 50],
                            "server_tool_use": ["web_search_requests": 2]])
        XCTAssertEqual(opus.cost(usage), (100 + 100 + 187.5 + 100) * 5 / 1_000_000 + 250 / 1_000_000 + 0.02, accuracy: 0.000001)
        let newHaiku = try XCTUnwrap(ModelCatalog.metadata(for: "claude-haiku-5-5").price)
        XCTAssertEqual(newHaiku.cost(AnthropicUsage(inputTokens: 200_000)), 0.1, accuracy: 0.000001)
        XCTAssertTrue(ModelCatalog.pricesAreStale(at: ModelCatalog.verificationDate.addingTimeInterval(91 * 86_400)))
        XCTAssertFalse(ModelCatalog.pricesAreStale(at: ModelCatalog.verificationDate))
    }

    func testSpendingLedgerSurvivesRelaunchAndUnknownChargesAndResetsNextUTCDate() {
        let name = "LedgerTests.\(UUID().uuidString)", date = ModelCatalog.verificationDate
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        SpendLedger(defaults: defaults).record(1.25, at: date)
        let ledger = SpendLedger(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(ledger.amount(at: date), 1.25)
        ledger.record(nil, at: date)
        XCTAssertTrue(ledger.isIncomplete(at: date))
        XCTAssertEqual(ledger.amount(at: date.addingTimeInterval(86_400)), 0)
        XCTAssertFalse(ledger.isIncomplete(at: date.addingTimeInterval(86_400)))
    }
}
