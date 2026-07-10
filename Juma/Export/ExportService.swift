import Foundation

/// Экспорт всех данных в Markdown и JSON — чтобы «скормить» базу знаний ChatGPT, Claude или Obsidian.
enum ExportService {

    // MARK: - Markdown

    static func markdown(tasks: [TaskItem], habits: [Habit], notes: [Note], transactions: [MoneyTransaction] = [], contacts: [Contact] = [], subscriptions: [Subscription] = []) -> String {
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

        // Финансы
        lines.append("")
        lines.append("## Финансы")
        if transactions.isEmpty {
            lines.append("_нет операций_")
        } else {
            let monthTransactions = transactions.filter {
                Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
            }
            let income = monthTransactions.filter { !$0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }
            let expenses = monthTransactions.filter(\.isExpense).reduce(Decimal(0)) { $0 + $1.amount }
            lines.append("Текущий месяц: доходы \(income.asCurrency), расходы \(expenses.asCurrency).")
            lines.append("")
            lines.append("| Дата | Сумма | Категория | Заметка |")
            lines.append("|---|---|---|---|")
            for transaction in transactions.sorted(by: { $0.date > $1.date }) {
                let sign = transaction.isExpense ? "−" : "+"
                lines.append("| \(transaction.date.formatted(date: .numeric, time: .omitted)) | \(sign)\(transaction.amount.asCurrency) | \(transaction.category) | \(transaction.note) |")
            }
        }

        // Подписки
        if !subscriptions.isEmpty {
            lines.append("")
            lines.append("## Подписки")
            let monthly = subscriptions.filter(\.isActive).reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
            lines.append("Итого в месяц: ~\(monthly.asCurrency)")
            for subscription in subscriptions {
                let period = subscription.period == .month ? "в месяц" : "в год"
                lines.append("- \(subscription.name): \(subscription.amount.asCurrency) \(period), следующее списание \(subscription.nextChargeDate.formatted(date: .numeric, time: .omitted))")
            }
        }

        // Люди (CRM)
        if !contacts.isEmpty {
            lines.append("")
            lines.append("## Люди (\(contacts.count))")
            for contact in contacts {
                var line = "- \(contact.fullName)"
                let job = [contact.position, contact.company].filter { !$0.isEmpty }.joined(separator: ", ")
                if !job.isEmpty { line += " — \(job)" }
                lines.append(line)
                if !contact.careerHistory.isEmpty {
                    for change in contact.careerHistory.split(separator: "\n") {
                        lines.append("  - смена работы: \(change)")
                    }
                }
                if !contact.notes.isEmpty {
                    lines.append("  - заметка: \(contact.notes)")
                }
            }
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

    struct ExportedTransaction: Codable {
        var amount: String
        var isExpense: Bool
        var category: String
        var note: String
        var date: Date
    }

    struct ExportedContact: Codable {
        var fullName: String
        var company: String
        var position: String
        var email: String
        var phone: String
        var linkedInURL: String
        var notes: String
        var careerHistory: String
    }

    struct ExportedSubscription: Codable {
        var name: String
        var amount: String
        var period: String
        var nextChargeDate: Date
        var isActive: Bool
    }

    struct ExportPayload: Codable {
        var app: String
        var exportedAt: Date
        var tasks: [ExportedTask]
        var habits: [ExportedHabit]
        var notes: [ExportedNote]
        var transactions: [ExportedTransaction]
        var contacts: [ExportedContact]
        var subscriptions: [ExportedSubscription]
    }

    static func json(tasks: [TaskItem], habits: [Habit], notes: [Note], transactions: [MoneyTransaction] = [], contacts: [Contact] = [], subscriptions: [Subscription] = []) throws -> Data {
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
            },
            transactions: transactions.map {
                ExportedTransaction(
                    amount: "\($0.amount)",
                    isExpense: $0.isExpense,
                    category: $0.category,
                    note: $0.note,
                    date: $0.date
                )
            },
            contacts: contacts.map {
                ExportedContact(
                    fullName: $0.fullName,
                    company: $0.company,
                    position: $0.position,
                    email: $0.email,
                    phone: $0.phone,
                    linkedInURL: $0.linkedInURL,
                    notes: $0.notes,
                    careerHistory: $0.careerHistory
                )
            },
            subscriptions: subscriptions.map {
                ExportedSubscription(
                    name: $0.name,
                    amount: "\($0.amount)",
                    period: $0.periodRaw,
                    nextChargeDate: $0.nextChargeDate,
                    isActive: $0.isActive
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
    static func writeFiles(tasks: [TaskItem], habits: [Habit], notes: [Note], transactions: [MoneyTransaction] = [], contacts: [Contact] = [], subscriptions: [Subscription] = []) throws -> (markdown: URL, json: URL) {
        let directory = FileManager.default.temporaryDirectory

        let markdownURL = directory.appendingPathComponent("Juma-Export.md")
        try markdown(tasks: tasks, habits: habits, notes: notes, transactions: transactions, contacts: contacts, subscriptions: subscriptions)
            .write(to: markdownURL, atomically: true, encoding: .utf8)

        let jsonURL = directory.appendingPathComponent("Juma-Export.json")
        try json(tasks: tasks, habits: habits, notes: notes, transactions: transactions, contacts: contacts, subscriptions: subscriptions)
            .write(to: jsonURL, options: .atomic)

        return (markdownURL, jsonURL)
    }
}
