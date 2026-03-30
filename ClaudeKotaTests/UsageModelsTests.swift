import Testing
@testable import ClaudeKota

@Suite struct UsageResponseParserTests {
    @Test func parseValidResponse() throws {
        let json = """
        {"five_hour": 0.42, "seven_day": 0.32}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(usage.fiveHour == 0.42)
        #expect(usage.sevenDay == 0.32)
    }

    @Test func parseWithExtraFields() throws {
        let json = """
        {"five_hour": 0.5, "seven_day": 0.1, "seven_day_opus": 0.05, "extra": "field"}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(usage.fiveHour == 0.5)
        #expect(usage.sevenDay == 0.1)
    }

    @Test func parseInvalidFormat() {
        let json = """
        {"unexpected": "format"}
        """.data(using: .utf8)!

        #expect(throws: UsageParseError.self) {
            try UsageResponseParser.parse(json)
        }
    }

    @Test func sessionRemainingCalculation() throws {
        let json = """
        {"five_hour": 0.42, "seven_day": 0.32}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(abs(usage.sessionRemaining - 0.58) < 0.001)
    }
}
