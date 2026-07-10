import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]

    @State private var searchText = ""
    @State private var editingNote: Note?
    @State private var isAddingNote = false
    @State private var isAskPresented = false
    @State private var isRecordingVoice = false
    @State private var isScanning = false

    private var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
                || $0.tags.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "База знаний пуста",
                        systemImage: "note.text",
                        description: Text("Записывайте сюда мысли, идеи и факты о себе — как в Obsidian. Поддерживается Markdown.")
                    )
                }
                ForEach(filteredNotes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        NoteRowView(note: note)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(filteredNotes[index])
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск по заметкам")
            .navigationTitle("Заметки")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAskPresented = true
                    } label: {
                        Label("Спросить базу", systemImage: "sparkle.magnifyingglass")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isAddingNote = true
                        } label: {
                            Label("Текстовая заметка", systemImage: "square.and.pencil")
                        }
                        Button {
                            isRecordingVoice = true
                        } label: {
                            Label("Голосовая заметка", systemImage: "mic")
                        }
                        Button {
                            isScanning = true
                        } label: {
                            Label("Скан документа (OCR)", systemImage: "doc.viewfinder")
                        }
                        .disabled(!DocumentScanView.isSupported)
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingNote) {
                NoteEditorView(note: nil)
            }
            .sheet(isPresented: $isAskPresented) {
                AskView()
            }
            .sheet(isPresented: $isRecordingVoice) {
                VoiceNoteView()
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScanView { text in
                    isScanning = false
                    saveScan(text)
                } onCancel: {
                    isScanning = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $editingNote) { note in
                NoteEditorView(note: note)
            }
        }
    }
}

extension NotesView {
    fileprivate func saveScan(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let title = String(localized: "Скан \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        let note = Note(title: title, content: trimmed, tags: String(localized: "скан"))
        modelContext.insert(note)
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Без названия" : note.title)
                .font(.headline)
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                ForEach(note.tagList, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Редактор заметки с режимом Markdown-просмотра.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let note: Note?

    @State private var title: String
    @State private var content: String
    @State private var tags: String
    @State private var isPreviewing = false

    init(note: Note?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
        _tags = State(initialValue: note?.tags ?? "")
    }

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("Заголовок", text: $title)
                        TextField("Теги через запятую", text: $tags)
                    }

                    Section {
                        Picker("Режим", selection: $isPreviewing) {
                            Text("Редактор").tag(false)
                            Text("Просмотр").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if isPreviewing {
                            Text(renderedMarkdown)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            TextEditor(text: $content)
                                .frame(minHeight: 220)
                                .font(.body.monospaced())
                        }
                    } footer: {
                        Text("Поддерживается Markdown: **жирный**, *курсив*, `код`, списки.")
                    }
                }
            }
            .navigationTitle(note == nil ? "Новая заметка" : "Заметка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        if let note {
            note.title = title
            note.content = content
            note.tags = tags
            note.modifiedAt = Date()
            note.embeddedAt = nil // заметка изменилась — вектор пересчитается при следующем поиске
        } else {
            let newNote = Note(title: title, content: content, tags: tags)
            modelContext.insert(newNote)
        }
        dismiss()
    }
}
