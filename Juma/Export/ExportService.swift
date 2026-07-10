import Foundation

/// Экспорт всех данных в Markdown и JSON — чтобы «скормить» базу знаний ChatGPT, Claude или Obsidian.
enum ExportService {

    // MARK: - Markdown

    static func markdown(tasks: [TaskItem], habits: [Habit], notes: [Note]) -> String {
        var lines: [String] = []
        let now = Date.now.formatted(date: .long, time: .shortened)

        lines.append("# Juma — моя база знаний")
        lines.append("")
        lines.append("> Это экспорт из моего приложения Juma (задачи, привычки, заметки).")
        lines.append("> Используй эти данные как контекст обо мне: помогай планировать, давай советы и отвечай на вопросы с их учётом.")
        lines.append("")
        lines.append("Дата экспорта: \(now)")

        // Задачи
        lines.append("")
        lines.append("## Задачи")
        let active = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone)

        lines.append("")
        lines.append("### Активные (\(active.count))")
        if active.isEmpty { lines.append("_нет_") }
        for task in active {
            var line = "- [ ] \(task.title) (приоритет: \(task.priority.title)"
            if let dueDate = task.dueDate {
                line += ", срок: \(dueDate.formatted(date: .numeric, time: .omitted))"
                if task.isOverdue { line += " — ПРОСРОЧЕНО" }
            }
            line += ")"
            lines.append(line)
            if !task.details.isEmpty {
                lines.append("  - \(task.details)")
            }
        }

        lines.append("")
        lines.append("### Выполненные (\(done.count))")
        if done.isEmpty { lines.append("_нет_") }
        for task in done {
            var line = "- [x] \(task.title)"
            if let completedAt = task.completedAt {
                line += " (выполнено: \(completedAt.formatted(date: .numeric, time: .omitted)))"
            }
            lines.append(line)
        }

        // Привычки
        lines.append("")
        lines.append("## Привычки")
        if habits.isEmpty { lines.append("_нет_") }
        for habit in habits {
            let status = habit.isCompleted(on: .now) ? "выполнена сегодня" : "сегодня не выполнена"
            lines.append("- \(habit.emoji) \(habit.name) — серия: \(habit.currentStreak) дн., \(status), всего отметок: \(habit.logs.count)")
        }

        // Заметки
        lines.append("")
        lines.append("## Заметки")
        if notes.isEmpty { lines.append("_нет_") }
        for note in notes {
            lines.append("")
            lines.append("### \(note.title.isEmpty ? "Без названия" : note.title)")
            if !note.tagList.isEmpty {
                lines.append("Теги: \(note.tagList.map { "#\($0)" }.joined(separator: " "))")
            }
            lines.append("Обновлено: \(note.modifiedAt.formatted(date: .numeric, time: .omitted))")
            lines.append("")
            lines.append(note.content)
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    struct ExportedTask: Codable {
        var title: String
        var details: String
        var priority: String
        var dueDate: Date?
        var isDone: Bool
        var createdAt: Date
        var completedAt: Date?
    }

    struct ExportedHabit: Codable {
        var name: String
        var emoji: String
        var currentStreak: Int
        var completedDates: [Date]
    }

    struct ExportedNote: Codable {
        var title: String
        var content: String
        var tags: [String]
        var createdAt: Date
        var modifiedAt: Date
    }

    struct ExportPayload: Codable {
        var app: String
        var exportedAt: Date
        var tasks: [ExportedTask]
        var habits: [ExportedHabit]
        var notes: [ExportedNote]
    }

    static func json(tasks: [TaskItem], habits: [Habit], notes: [Note]) throws -> Data {
        let payload = ExportPayload(
            app: "Juma",
            exportedAt: Date(),
            tasks: tasks.map {
                ExportedTask(
                    title: $0.title,
                    details: $0.details,
                    priority: $0.priority.title,
                    dueDate: $0.dueDate,
                    isDone: $0.isDone,
                    createdAt: $0.createdAt,
                    completedAt: $0.completedAt
                )
            },
            habits: habits.map {
                ExportedHabit(
                    name: $0.name,
                    emoji: $0.emoji,
                    currentStreak: $0.currentStreak,
                    completedDates: $0.logs.map(\.date).sorted()
                )
            },
            notes: notes.map {
                ExportedNote(
                    title: $0.title,
                    content: $0.content,
                    tags: $0.tagList,
                    createdAt: $0.createdAt,
                    modifiedAt: $0.modifiedAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    // MARK: - Запись файлов

    /// Пишет оба файла во временную папку и возвращает URL для ShareLink.
    static func writeFiles(tasks: [TaskItem], habits: [Habit], notes: [Note]) throws -> (markdown: URL, json: URL) {
        let directory = FileManager.default.temporaryDirectory

        let markdownURL = directory.appendingPathComponent("Juma-Export.md")
        try markdown(tasks: tasks, habits: habits, notes: notes)
            .write(to: markdownURL, atomically: true, encoding: .utf8)

        let jsonURL = directory.appendingPathComponent("Juma-Export.json")
        try json(tasks: tasks, habits: habits, notes: notes)
            .write(to: jsonURL, options: .atomic)

        return (markdownURL, jsonURL)
    }
}
