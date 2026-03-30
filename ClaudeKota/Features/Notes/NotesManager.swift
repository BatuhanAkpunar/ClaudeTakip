import Foundation

@Observable @MainActor
final class NotesManager {
    private(set) var settings: AppSettings
    private let userDefaultsKey = "ClaudeKota.AppSettings"
    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        if let data = store.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaultSettings
        }
    }

    func addNote(title: String, content: String) {
        guard settings.notes.count < NoteConstants.maxNotes else { return }
        let trimmedTitle = String(title.prefix(NoteConstants.maxTitleLength))
        let trimmedContent = String(content.prefix(NoteConstants.maxContentLength))
        let note = Note(title: trimmedTitle, content: trimmedContent)
        settings.notes.insert(note, at: 0)
        save()
    }

    func deleteNote(id: UUID) {
        settings.notes.removeAll { $0.id == id }
        save()
    }

    func updateNote(id: UUID, title: String, content: String) {
        guard let index = settings.notes.firstIndex(where: { $0.id == id }) else { return }
        settings.notes[index].title = String(title.prefix(NoteConstants.maxTitleLength))
        settings.notes[index].content = String(content.prefix(NoteConstants.maxContentLength))
        save()
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            store.set(data, forKey: userDefaultsKey)
        }
    }
}
