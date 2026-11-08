import XCTest
@testable import TatvaumConnect

final class GuardrailTests: XCTestCase {
    func testEvaluate() {
        XCTAssertEqual(ChatGuardrail.evaluate("Show me PORN")?.category, .Sexual)
        XCTAssertEqual(ChatGuardrail.evaluate("I will Murder him")?.matchedTerm, "murder")
        XCTAssertNil(ChatGuardrail.evaluate("I feel calm after my morning meditation"))
        XCTAssertTrue(ChatGuardrail.fallbackMessage(.init(category: .Violence, matchedTerm: "x")).contains("crisis line"))
    }

    func testRankModels() {
        let ids = ["models/gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.0-flash-lite", "gemini-2.5-flash-preview-05-20",
                   "gemini-2.5-pro", "gemini-3.0-flash", "gemini-2.5-flash"]
        XCTAssertEqual(GeminiClient.rankModels(ids),
                       ["gemini-3.0-flash-lite", "gemini-2.5-flash-lite", "gemini-3.0-flash", "gemini-2.5-flash"])
        XCTAssertEqual(GeminiClient.suggestedModel("use models/gemini-1.5-flash for x, models/gemini-3.5-flash-lite for y"), "gemini-3.5-flash-lite")
        XCTAssertNil(GeminiClient.suggestedModel("nothing"))
    }

    func testResponseParsing() {
        let ok = #"{"choices":[{"message":{"content":"  hi \n"}}]}"#
        XCTAssertEqual(GeminiClient.parseCompletion(Data(ok.utf8)), "hi")
        XCTAssertNil(GeminiClient.parseCompletion(Data("{}".utf8)))
        XCTAssertEqual(GeminiClient.parseStreamChunk(#"{"choices":[{"delta":{"content":"yo"}}]}"#), .delta("yo"))
        XCTAssertEqual(GeminiClient.parseStreamChunk(#"{"choices":[{"delta":{}}]}"#), .skip)
        XCTAssertEqual(GeminiClient.parseStreamChunk("garbage"), .skip)
        XCTAssertEqual(GeminiClient.parseStreamChunk(#"{"error":{"message":"boom"}}"#), .error("boom"))
    }

    func testExtractJsonObjectAndEssentials() {
        let j = LLMService.extractJsonObject("```json\n{\"traits\":[\"a\"]}\n```")
        XCTAssertEqual(j?["traits"] as? [String], ["a"])
        XCTAssertNil(LLMService.extractJsonObject("no json"))
        XCTAssertEqual(LLMService.chartEssentials("====\nAsc: Leo\n\n----\nMoon: Aries\nHOUSE TABLE\n1 x"), "Asc: Leo\nMoon: Aries")
    }
}
