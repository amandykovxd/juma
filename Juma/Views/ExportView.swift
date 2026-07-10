import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query private var habits: [Habit]
    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]
    @Query private var transactions: [MoneyTransaction]

    @State private var markdownURL: URL?
    @State private var jsonURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Экспортируйте все данные (задачи, привычки, заметки) одним файлом и загрузите его в ChatGPT или Claude — так у ассистента появится база знаний о вас.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Для ChatGPT / Claude")
                }

                Section("Файлы") {
                    if let markdownURL {
                        ShareLink(item: markdownURL) {
                            Label("Поделиться Markdown (.md)", systemImage: "doc.text")
                        }
                    }
                    if let jsonURL {
                        ShareLink(item: jsonURL) {
                            Label("Поделиться JSON (.json)", systemImage: "curlybraces")
                        }
                    }
                    Button {
                        generate()
                    } label: {
                        Label(markdownURL == nil ? "Сгенерировать файлы" : "Обновить файлы", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Что внутри") {
                    LabeledContent("Задачи", value: "\(tasks.count)")
                    LabeledContent("Привычки", value: "\(habits.count)")
                    LabeledContent("Заметки", value: "\(notes.count)")
                    LabeledContent("Операции", value: "\(transactions.count)")
                }
            }
            .navigationTitle("Экспорт")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear {
                generate()
            }
        }
    }

    private func generate() {
        do {
            let urls = try ExportService.writeFiles(tasks: tasks, habits: habits, notes: notes, transactions: transactions)
            markdownURL = urls.markdown
            jsonURL = urls.json
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось подготовить файлы: \(error.localizedDescription)"
        }
    }
}
