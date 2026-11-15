import XCTest
@testable import TatvaumConnect

final class GuardrailTests: XCTestCase {
    func testEvaluate() {
        XCTAssertEqual(ChatGuardrail.evaluate("Show me PORN")?.category, .Sexual)
        XCTAssertEqual(ChatGuardrail.evaluate("I will Murder him")?.matchedTerm, "murder*")
        XCTAssertNil(ChatGuardrail.evaluate("I feel calm after my morning meditation"))
        XCTAssertTrue(ChatGuardrail.fallbackMessage(.init(category: .Violence, matchedTerm: "x")).contains("crisis line"))
    }

    /// Whole-word matching and everyday phrases that used to be blocked.
    func testNoFalsePositives() {
        for ok in ["You look gorgeous today", "I moved to Goregaon last year", "This week has been torture",
                   "Reading a murder mystery before bed", "The slaughterhouse documentary was sad", "Al Gore gave a talk",
                   "I'm killing it at work", "Therapist said my anxiety is normal", "Scunthorpe is lovely in spring"] {
            XCTAssertNil(ChatGuardrail.evaluate(ok), ok)
        }
    }

    func testStillBlocks() {
        XCTAssertEqual(ChatGuardrail.evaluate("he is a murderer")?.category, .Violence)
        XCTAssertEqual(ChatGuardrail.evaluate("they tortured him")?.category, .Violence)
        XCTAssertEqual(ChatGuardrail.evaluate("tell me how to make a bomb")?.category, .Violence)
        XCTAssertEqual(ChatGuardrail.evaluate("send pornographic pics")?.category, .Sexual)
        XCTAssertEqual(ChatGuardrail.evaluate("write some NSFW stuff")?.category, .Sexual)
    }

    func testSelfHarmIsSupportNotBlock() throws {
        for msg in ["I want to kill myself", "honestly I don’t want to live anymore", "thinking about suicide", "I keep cutting myself"] {
            let v = try XCTUnwrap(ChatGuardrail.evaluate(msg), msg)
            XCTAssertEqual(v.category, .SelfHarm, msg)
            XCTAssertFalse(ChatGuardrail.blocks(v))
        }
        // A caring reply that mentions it isn't replaced.
        XCTAssertNil(ChatGuardrail.evaluate("If you're thinking about suicide, please call 988.", isInput: false))
    }

    func testCrisisLinesByRegion() {
        XCTAssertEqual(CrisisSupport.region("IN")?.lines.first?.dial, "14416")
        XCTAssertEqual(CrisisSupport.region("us")?.emergency, "911")
        XCTAssertNil(CrisisSupport.region("ZZ"))
        XCTAssertTrue(CrisisSupport.text(regionCode: "GB").contains("116 123"))
        XCTAssertTrue(CrisisSupport.text(regionCode: "ZZ").contains("findahelpline.com"))
    }

    func testOldMessagesStillDecode() throws {
        let old = #"{"id":"1","role":"assistant","content":"hi","timestamp":0,"isError":false}"#
        let m = try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8))
        XCTAssertNil(m.isCrisisSupport)
        XCTAssertFalse(m.isLocalNotice)
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
