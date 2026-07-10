import SwiftUI
import SwiftData
import FoundationModels

/// «Что я знаю о X»: семантический поиск по заметкам + ответ локальной модели (RAG).
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]

    enum Phase {
        case indexing(done: Int, total: Int)
        case ready
        case thinking
        case answer(text: String, sources: [Note])
        case empty
        case error(String)
    }

    @State private var question = ""
    @State private var phase: Phase = .ready

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например: что я знаю о питании?", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        ask()
                    } label: {
                        Label("Спросить", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || !canAsk)
                } footer: {
                    Text("Поиск идёт по смыслу, а не по словам. Вся обработка — на устройстве.")
                }

                resultSection
            }
            .navigationTitle("Спросить базу")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                await buildIndex()
            }
        }
    }

    private var canAsk: Bool {
        switch phase {
        case .indexing, .thinking: false
        default: true
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch phase {
        case .ready:
            EmptyView()

        case .indexing(let done, let total):
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Индексация заметок… \(done)/\(total)")
                        .foregroundStyle(.secondary)
                }
            }

        case .thinking:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Ищу и думаю…")
                        .foregroundStyle(.secondary)
                }
            }

        case .answer(let text, let sources):
            Section("Ответ") {
                Text(text)
            }
            Section("Источники") {
                ForEach(sources) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title.isEmpty ? "Без названия" : note.title)
                            .font(.subheadline.weight(.medium))
                        Text(note.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

        case .empty:
            Section {
                ContentUnavailableView(
                    "Ничего не нашлось",
                    systemImage: "magnifyingglass",
                    description: Text("По этому вопросу в заметках пока пусто. Добавьте заметки — и база знаний начнёт отвечать.")
                )
            }

        case .error(let message):
            Section {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    // MARK: - Индексация

    /// Считает вектора для новых и изменённых заметок.
    private func buildIndex() async {
        let stale = notes.filter { note in
            guard let embeddedAt = note.embeddedAt else { return true }
            return embeddedAt < note.modifiedAt
        }
        guard !stale.isEmpty else { return }

        phase = .indexing(done: 0, total: stale.count)
        do {
            try await EmbeddingService.shared.prepare()
            for (index, note) in stale.enumerated() {
                let text = "\(note.title)\n\(note.tags)\n\(note.content)"
                note.embedding = try? EmbeddingService.shared.embed(text)
                note.embeddedAt = Date()
                phase = .indexing(done: index + 1, total: stale.count)
                await Task.yield()
            }
            phase = .ready
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Вопрос

    private func ask() {
        let query = question.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        phase = .thinking

        Task {
            do {
                try await EmbeddingService.shared.prepare()
                let queryVector = try EmbeddingService.shared.embed(query)

                let ranked = notes
                    .compactMap { note -> (note: Note, score: Double)? in
                        guard let embedding = note.embedding else { return nil }
                        return (note, EmbeddingService.cosineSimilarity(queryVector, embedding))
                    }
                    .sorted { $0.score > $1.score }
                    .prefix(3)
                    .filter { $0.score > 0.2 }

                guard !ranked.isEmpty else {
                    phase = .empty
                    return
                }

                let sources = ranked.map(\.note)
                if let answer = await llmAnswer(question: query, sources: sources) {
                    phase = .answer(text: answer, sources: sources)
                } else {
                    phase = .answer(
                        text: "Локальная модель недоступна, но вот самые близкие по смыслу заметки:",
                        sources: sources
                    )
                }
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func llmAnswer(question: String, sources: [Note]) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let context = sources
            .map { "### \($0.title.isEmpty ? "Без названия" : $0.title)\n\(String($0.content.prefix(800)))" }
            .joined(separator: "\n\n")

        let session = LanguageModelSession(instructions: """
            Ты — ассистент личной базы знаний в приложении Juma. \
            Отвечай на вопрос пользователя кратко и по делу, на русском языке, \
            опираясь ТОЛЬКО на переданные заметки. Если в заметках нет ответа — честно скажи об этом.
            """)
        let response = try? await session.respond(
            to: "Вопрос: \(question)\n\nЗаметки:\n\(context)"
        )
        return response?.content
    }
}
