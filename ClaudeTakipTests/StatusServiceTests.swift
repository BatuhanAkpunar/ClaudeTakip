import Testing
@testable import ClaudeTakip

@Suite struct StatusParserTests {
    @Test func parseOperational() throws {
        let json = """
        {"status":{"indicator":"none","description":"All Systems Operational"}}
        """.data(using: .utf8)!
        let status = try StatusResponseParser.parse(json)
        #expect(status == .operational)
    }

    @Test func parseMajor() throws {
        let json = """
        {"status":{"indicator":"major","description":"Major System Outage"}}
        """.data(using: .utf8)!
        let status = try StatusResponseParser.parse(json)
        #expect(status == .major)
    }

    @Test func parseDegraded() throws {
        let json = """
        {"status":{"indicator":"minor","description":"Degraded"}}
        """.data(using: .utf8)!
        let status = try StatusResponseParser.parse(json)
        #expect(status == .degraded)
    }
}
