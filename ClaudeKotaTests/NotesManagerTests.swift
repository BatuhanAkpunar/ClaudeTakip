import Foundation
import Testing
@testable import ClaudeKota

@Suite @MainActor struct NotesManagerTests {

    private func makeManager() -> NotesManager {
        let suiteName = "NotesManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return NotesManager(store: defaults)
    }

    @Test func addNote() {
        let manager = makeManager()
        manager.addNote(title: "Test", content: "Content")
        #expect(manager.settings.notes.count == 1)
        #expect(manager.settings.notes.first?.title == "Test")
    }

    @Test func deleteNote() {
        let manager = makeManager()
        manager.addNote(title: "ToDelete", content: "Content")
        let noteId = manager.settings.notes.first!.id
        manager.deleteNote(id: noteId)
        #expect(manager.settings.notes.isEmpty)
    }

    @Test func updateNote() {
        let manager = makeManager()
        manager.addNote(title: "Old", content: "Old content")
        let noteId = manager.settings.notes.first!.id
        manager.updateNote(id: noteId, title: "New", content: "New content")
        #expect(manager.settings.notes.first?.title == "New")
        #expect(manager.settings.notes.first?.content == "New content")
    }

    @Test func maxNotesLimit() {
        let manager = makeManager()
        for i in 0..<55 {
            manager.addNote(title: "Note \(i)", content: "Content")
        }
        #expect(manager.settings.notes.count == NoteConstants.maxNotes)
    }

    @Test func titleTruncation() {
        let manager = makeManager()
        let longTitle = String(repeating: "A", count: 200)
        manager.addNote(title: longTitle, content: "Content")
        #expect(manager.settings.notes.first!.title.count == NoteConstants.maxTitleLength)
    }
}
