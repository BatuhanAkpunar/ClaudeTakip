import Testing
@testable import ClaudeTakip

@Suite struct UsageResponseParserTests {
    @Test func parseValidResponse() throws {
        let json = """
        {"five_hour": {"utilization": 42.0, "resets_at": "2025-11-04T04:59:59.943648+00:00"}, "seven_day": {"utilization": 35.0, "resets_at": "2025-11-06T03:59:59.000000+00:00"}}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(abs(usage.fiveHourUtilization - 0.42) < 0.001)
        #expect(abs(usage.sevenDayUtilization - 0.35) < 0.001)
        #expect(usage.fiveHourResetsAt != nil)
        #expect(usage.sevenDayResetsAt != nil)
    }

    @Test func parseWithExtraFields() throws {
        let json = """
        {"five_hour": {"utilization": 50.0, "resets_at": null}, "seven_day": {"utilization": 10.0, "resets_at": null}, "seven_day_opus": {"utilization": 5.0, "resets_at": "2025-11-06T03:59:59.000000+00:00"}, "iguana_necktie": null}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(abs(usage.fiveHourUtilization - 0.50) < 0.001)
        #expect(abs(usage.sevenDayUtilization - 0.10) < 0.001)
    }

    @Test func parseFullAPIResponse() throws {
        let json = """
        {"five_hour":{"utilization":37.0,"resets_at":"2025-11-04T04:59:59.943648+00:00"},"seven_day":{"utilization":26.0,"resets_at":"2025-11-06T03:59:59.771647+00:00"},"seven_day_opus":{"utilization":0.0,"resets_at":null},"seven_day_sonnet":{"utilization":1.0,"resets_at":"2025-11-07T20:59:59.771655+00:00"},"seven_day_oauth_apps":null,"iguana_necktie":null,"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null}}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(abs(usage.fiveHourUtilization - 0.37) < 0.001)
        #expect(abs(usage.sevenDayUtilization - 0.26) < 0.001)
        #expect(usage.sonnetUtilization != nil)
        #expect(abs(usage.sonnetUtilization! - 0.01) < 0.001)
        #expect(usage.sonnetResetsAt != nil)
        #expect(usage.extraUsage != nil)
        #expect(usage.extraUsage?.isEnabled == false)
        #expect(usage.extraUsage?.monthlyLimit == nil)
    }

    @Test func toCachedUsageConversion() throws {
        let json = """
        {"five_hour":{"utilization":42.0,"resets_at":"2025-11-04T04:59:59.000000+00:00"},"seven_day":{"utilization":35.0,"resets_at":"2025-11-06T03:59:59.000000+00:00"}}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        let cached = usage.toCachedUsage()
        #expect(abs(cached.fiveHour!.utilization - 0.42) < 0.001)
        #expect(abs(cached.sevenDay!.utilization - 0.35) < 0.001)
        #expect(cached.fiveHour!.resetsAt != nil)
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
        {"five_hour": {"utilization": 42.0, "resets_at": null}, "seven_day": {"utilization": 32.0, "resets_at": null}}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(abs(usage.sessionRemaining - 0.58) < 0.001)
    }

    @Test func parseNullBuckets() throws {
        let json = """
        {"five_hour": {"utilization": 0.0, "resets_at": null}, "seven_day": null}
        """.data(using: .utf8)!

        let usage = try UsageResponseParser.parse(json)
        #expect(usage.fiveHourUtilization == 0.0)
        #expect(usage.sevenDayUtilization == 0.0)
        #expect(usage.sevenDayResetsAt == nil)
    }
}
