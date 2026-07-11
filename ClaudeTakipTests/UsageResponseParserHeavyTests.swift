import Testing
import Foundation
@testable import ClaudeTakip

/// Heavy edge-case coverage for UsageResponseParser: number-type coercion,
/// out-of-range utilization, assorted date formats, and malformed payloads.
@Suite struct UsageResponseParserHeavyTests {

    private func parse(_ s: String) throws -> UsageData {
        try UsageResponseParser.parse(Data(s.utf8))
    }

    // MARK: - Number coercion

    @Test func integerUtilizationIsAccepted() throws {
        // JSON integers (no decimal point) must still coerce to Double.
        let usage = try parse(#"{"five_hour":{"utilization":50},"seven_day":{"utilization":10}}"#)
        #expect(abs(usage.fiveHourUtilization - 0.50) < 0.0001)
        #expect(abs(usage.sevenDayUtilization - 0.10) < 0.0001)
    }

    @Test func stringUtilizationIsTreatedAsMissing() throws {
        // A stringly-typed value must not crash; both missing → throws.
        #expect(throws: UsageParseError.self) {
            _ = try parse(#"{"five_hour":{"utilization":"50"},"seven_day":{"utilization":"10"}}"#)
        }
    }

    // MARK: - Out-of-range utilization

    @Test func utilizationAboveHundredIsPreservedAndRemainingClampsToZero() throws {
        let usage = try parse(#"{"five_hour":{"utilization":105},"seven_day":{"utilization":0}}"#)
        #expect(abs(usage.fiveHourUtilization - 1.05) < 0.0001)
        #expect(usage.sessionRemaining == 0.0)
    }

    // MARK: - Date formats

    @Test func dateWithoutFractionalSecondsParses() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10,"resets_at":"2025-11-04T04:59:59+00:00"},"seven_day":{"utilization":10}}"#)
        #expect(usage.fiveHourResetsAt != nil)
    }

    @Test func dateWithZuluZoneParses() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10,"resets_at":"2025-11-04T04:59:59.943648Z"},"seven_day":{"utilization":10}}"#)
        #expect(usage.fiveHourResetsAt != nil)
    }

    @Test func malformedDateBecomesNilWithoutThrowing() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10,"resets_at":"not-a-date"},"seven_day":{"utilization":10}}"#)
        #expect(usage.fiveHourResetsAt == nil)
    }

    // MARK: - extra_usage

    @Test func extraUsageIntegerBalanceCoercesToDouble() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10},"extra_usage":{"is_enabled":true,"current_balance":500}}"#)
        #expect(usage.extraUsage?.isEnabled == true)
        #expect(usage.extraUsage?.currentBalance == 500.0)
    }

    @Test func extraUsageWithoutIsEnabledIsNil() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10},"extra_usage":{"monthly_limit":100}}"#)
        #expect(usage.extraUsage == nil)
    }

    // MARK: - Malformed / missing payloads

    @Test func emptyDataThrows() {
        #expect(throws: UsageParseError.self) {
            _ = try UsageResponseParser.parse(Data())
        }
    }

    @Test func jsonArrayInsteadOfObjectThrows() {
        #expect(throws: UsageParseError.self) {
            _ = try parse("[1,2,3]")
        }
    }

    @Test func onlyFiveHourBucketDefaultsWeeklyToZero() throws {
        let usage = try parse(#"{"five_hour":{"utilization":20}}"#)
        #expect(abs(usage.fiveHourUtilization - 0.20) < 0.0001)
        #expect(usage.sevenDayUtilization == 0.0)
    }

    @Test func bothBucketsPresentButUtilizationNullThrows() {
        #expect(throws: UsageParseError.self) {
            _ = try parse(#"{"five_hour":{"resets_at":null},"seven_day":{"resets_at":null}}"#)
        }
    }

    @Test func modelBucketKeywordMatchIsScaled() throws {
        let usage = try parse(#"{"five_hour":{"utilization":10},"seven_day":{"utilization":10},"seven_day_sonnet":{"utilization":80}}"#)
        #expect(usage.sonnetUtilization != nil)
        #expect(abs((usage.sonnetUtilization ?? 0) - 0.80) < 0.0001)
    }

    // MARK: - New API shape: weekly_scoped limit in the limits array

    @Test func weeklyScopedLimitSuppliesModelNameAndUtilization() throws {
        // Real API sample: legacy seven_day_sonnet is null; the live model-scoped
        // weekly limit lives in the limits array as kind == "weekly_scoped".
        let json = #"""
        {
          "five_hour": {"utilization": 3.0, "resets_at": "2026-07-09T17:49:59.718434+00:00"},
          "seven_day": {"utilization": 62.0, "resets_at": "2026-07-11T06:59:59.718457+00:00"},
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "extra_usage": {"is_enabled": false},
          "limits": [
            {"kind":"session","group":"session","percent":3,"severity":"normal","resets_at":"2026-07-09T17:49:59.718434+00:00","scope":null,"is_active":false},
            {"kind":"weekly_all","group":"weekly","percent":62,"severity":"normal","resets_at":"2026-07-11T06:59:59.718457+00:00","scope":null,"is_active":false},
            {"kind":"weekly_scoped","group":"weekly","percent":100,"severity":"critical","resets_at":"2026-07-11T06:59:59.718734+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}
          ]
        }
        """#
        let usage = try parse(json)
        #expect(usage.modelLimitName == "Fable")
        #expect(usage.sonnetUtilization != nil)
        #expect(abs((usage.sonnetUtilization ?? 0) - 1.0) < 0.0001)
        #expect(usage.sonnetResetsAt != nil)
    }

    @Test func weeklyScopedPrefersActiveEntry() throws {
        // Two weekly_scoped entries; the active one wins.
        let json = #"""
        {
          "five_hour": {"utilization": 3},
          "seven_day": {"utilization": 62},
          "limits": [
            {"kind":"weekly_scoped","percent":40,"scope":{"model":{"display_name":"Sonnet"}},"is_active":false},
            {"kind":"weekly_scoped","percent":100,"scope":{"model":{"display_name":"Fable"}},"is_active":true}
          ]
        }
        """#
        let usage = try parse(json)
        #expect(usage.modelLimitName == "Fable")
        #expect(abs((usage.sonnetUtilization ?? 0) - 1.0) < 0.0001)
    }

    @Test func legacyFallbackWhenNoLimitsArray() throws {
        // No limits array, but legacy seven_day_sonnet present — fall back to it,
        // and modelLimitName stays nil.
        let usage = try parse(#"{"five_hour":{"utilization":10},"seven_day":{"utilization":10},"seven_day_sonnet":{"utilization":80}}"#)
        #expect(usage.modelLimitName == nil)
        #expect(abs((usage.sonnetUtilization ?? 0) - 0.80) < 0.0001)
    }
}
