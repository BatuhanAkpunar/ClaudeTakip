import SwiftUI

struct NotesPanelView: View {
    @Bindable var notesManager: NotesManager
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var editingNoteId: UUID?
    @State private var hoveredNoteId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notlar").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: clearEditing) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(DT.Colors.cardBackground, in: RoundedRectangle(cornerRadius: DT.Radius.iconButton))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(notesManager.settings.notes) { note in
                        NoteItemView(
                            note: note,
                            isHovered: hoveredNoteId == note.id,
                            onEdit: { startEditing(note) },
                            onDelete: { notesManager.deleteNote(id: note.id) }
                        )
                        .onHover { isHovered in hoveredNoteId = isHovered ? note.id : nil }
                    }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                TextField("Başlık...", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(8)
                    .background(DT.Colors.cardBackground, in: RoundedRectangle(cornerRadius: DT.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).strokeBorder(DT.Colors.cardBorder, lineWidth: 0.5))

                TextField("Not içeriğini yaz...", text: $newContent, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .lineLimit(2...4)
                    .padding(8)
                    .background(DT.Colors.cardBackground, in: RoundedRectangle(cornerRadius: DT.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).strokeBorder(DT.Colors.cardBorder, lineWidth: 0.5))

                if editingNoteId != nil {
                    HStack {
                        Button("Vazgeç") { clearEditing() }
                            .buttonStyle(.plain).font(DT.Typography.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Kaydet") { saveEdit() }
                            .buttonStyle(.plain).font(DT.Typography.caption).foregroundStyle(DT.Colors.statusGreen)
                    }
                } else if !newTitle.isEmpty || !newContent.isEmpty {
                    HStack {
                        Spacer()
                        Button("Ekle") { addNote() }
                            .buttonStyle(.plain).font(DT.Typography.caption).foregroundStyle(DT.Colors.statusGreen)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: DT.Size.notesPanelWidth)
    }

    private func addNote() {
        guard !newTitle.isEmpty else { return }
        notesManager.addNote(title: newTitle, content: newContent)
        newTitle = ""; newContent = ""
    }

    private func startEditing(_ note: Note) {
        editingNoteId = note.id; newTitle = note.title; newContent = note.content
    }

    private func saveEdit() {
        guard let id = editingNoteId else { return }
        notesManager.updateNote(id: id, title: newTitle, content: newContent)
        clearEditing()
    }

    private func clearEditing() {
        editingNoteId = nil; newTitle = ""; newContent = ""
    }
}

struct NoteItemView: View {
    let note: Note
    let isHovered: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer()
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .background(DT.Colors.hoverHighlight, in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                        Button(action: onDelete) {
                            Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.red)
                                .frame(width: 20, height: 20)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text(note.content)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DT.Radius.card).fill(isHovered ? DT.Colors.hoverHighlight : DT.Colors.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).strokeBorder(DT.Colors.cardBorder, lineWidth: 0.5))
        .help(note.content.count > 80 ? note.content : "")
    }
}
