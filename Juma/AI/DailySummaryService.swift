import Foundation
import FoundationModels

/// Структурированная сводка дня, которую генерирует локальная модель Apple Intelligence.
@Generable
struct DailySummary {
    @Guide(description: "Дружелюбная сводка дня в 2–3 предложениях на русском языке")
    var overview: String

    @Guide(description: "Самое важное на сегодня, одно предложение на русском языке")
    var mainFocus: String

    @Guide(description: "Короткий практичный совет по задачам, 1–2 предложения на русском языке")
    var taskAdvice: String

    @Guide(description: "Короткий совет по привычкам с учётом серий, 1–2 предложения на русском языке")
    var habitAdvice: String
}

enum SummaryOutcome {
    /// Сводка от локальной LLM.
    case ai(DailySummary)
    /// Модель недоступна или упала — детерминированная сводка + причина.
    case fallback(text: String, note: String)
}

enum DailySummaryService {

    /// `context` и `fallbackText` готовятся на главном акторе из SwiftData-моделей,
    /// сюда передаются уже готовые строки.
    static func makeSummary(context: String, fallbackText: String) async -> SummaryOutcome {
        let model = SystemLanguageModel.default

        guard case .available = model.availability else {
            return .fallback(text: fallbackText, note: unavailabilityMessage(model.availability))
        }

        do {
            let session = LanguageModelSession(instructions: """
                Ты — личный ассистент в приложении Juma для управления жизнью. \
                Твоя задача — составлять краткую, конкретную и дружелюбную сводку дня \
                на русском языке по задачам и привычкам пользователя. \
                Опирайся только на переданные данные, ничего не выдумывай.
                """)
            let response = try await session.respond(
                to: "Составь сводку дня по этим данным.\n\n\(context)",
                generating: DailySummary.self
            )
            return .ai(response.content)
        } catch {
            return .fallback(text: fallbackText, note: "Не удалось сгенерировать AI-сводку: \(error.localizedDescription)")
        }
    }

    private static func unavailabilityMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(.deviceNotEligible):
            return "Это устройство не поддерживает Apple Intelligence — показана обычная сводка."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence выключен. Включите его в Настройках, чтобы получать AI-сводку."
        case .unavailable(.modelNotReady):
            return "Локальная модель ещё загружается. Попробуйте чуть позже."
        case .unavailable:
            return "Локальная модель сейчас недоступна — показана обычная сводка."
        }
    }

    // MARK: - Подготовка контекста (вызывается на главном акторе)

    static func contextDescription(tasks: [TaskItem], habits: [Habit]) -> String {
        var lines: [String] = []
        let today = Date.now.formatted(date: .long, time: .omitted)
        lines.append("Сегодня: \(today).")

        let active = tasks.filter { !$0.isDone }
        let overdue = active.filter(\.isOverdue)
        let dueToday = active.filter(\.isDueToday)
        let doneToday = tasks.filter {
            guard let completedAt = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }

        lines.append("\nЗадачи: всего активных — \(active.count), просроченных — \(overdue.count), на сегодня — \(dueToday.count), выполнено сегодня — \(doneToday.count).")
        for task in overdue.prefix(5) {
            lines.append("- ПРОСРОЧЕНО: \(task.title) (приоритет: \(task.priority.title))")
        }
        for task in dueToday.prefix(5) {
            lines.append("- На сегодня: \(task.title) (приоритет: \(task.priority.title))")
        }
        for task in active.filter({ !$0.isOverdue && !$0.isDueToday }).prefix(5) {
            lines.append("- В работе: \(task.title) (приоритет: \(task.priority.title))")
        }

        lines.append("\nПривычки:")
        if habits.isEmpty {
            lines.append("- пока не заведены")
        }
        for habit in habits {
            let status = habit.isCompleted(on: .now) ? "сегодня выполнена" : "сегодня ещё не выполнена"
            lines.append("- \(habit.name): серия \(habit.currentStreak) дн., \(status)")
        }

        return lines.joined(separator: "\n")
    }

    static func ruleBasedSummary(tasks: [TaskItem], habits: [Habit]) -> String {
        let active = tasks.filter { !$0.isDone }
        let overdue = active.filter(\.isOverdue)
        let dueToday = active.filter(\.isDueToday)
        let pendingHabits = habits.filter { !$0.isCompleted(on: .now) }

        var parts: [String] = []

        if active.isEmpty {
            parts.append("Активных задач нет — можно спланировать что-то новое.")
        } else {
            parts.append("Активных задач: \(active.count).")
            if !overdue.isEmpty {
                parts.append("Просрочено: \(overdue.count) — начните с «\(overdue[0].title)».")
            } else if !dueToday.isEmpty {
                parts.append("На сегодня: \(dueToday.count) — главная: «\(dueToday[0].title)».")
            }
        }

        if habits.isEmpty {
            parts.append("Заведите первую привычку, чтобы отслеживать серии.")
        } else if pendingHabits.isEmpty {
            parts.append("Все привычки на сегодня выполнены — отлично!")
        } else {
            let names = pendingHabits.prefix(3).map(\.name).joined(separator: ", ")
            parts.append("Осталось по привычкам: \(names).")
        }

        return parts.joined(separator: " ")
    }
}
