import Foundation
import Testing
@testable import ClaudeTakip

@Suite(.serialized) struct KeychainServiceTests {
    let service = KeychainService()
    let testAccount = "test-account-\(UUID().uuidString)"

    @Test func saveAndRetrieve() throws {
        try service.save(key: testAccount, value: "test-value")
        let retrieved = try service.retrieve(key: testAccount)
        #expect(retrieved == "test-value")
        try service.delete(key: testAccount)
    }

    @Test func deleteKey() throws {
        try service.save(key: testAccount, value: "to-delete")
        try service.delete(key: testAccount)
        let retrieved = try? service.retrieve(key: testAccount)
        #expect(retrieved == nil)
    }

    @Test func updateExistingKey() throws {
        try service.save(key: testAccount, value: "old-value")
        try service.save(key: testAccount, value: "new-value")
        let retrieved = try service.retrieve(key: testAccount)
        #expect(retrieved == "new-value")
        try service.delete(key: testAccount)
    }

    @Test func retrieveNonExistent() {
        let retrieved = try? service.retrieve(key: "nonexistent-\(UUID().uuidString)")
        #expect(retrieved == nil)
    }
}
