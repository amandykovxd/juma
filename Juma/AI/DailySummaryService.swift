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

    @Guide(description: "Короткий совет по здоровью и финансам на основе шагов, сна и расходов, 1–2 предложения на русском языке")
    var healthAdvice: String
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
                по задачам, привычкам, финансам и здоровью пользователя. \
                Опирайся только на переданные данные, ничего не выдумывай. \
                \(responseLanguageInstruction)
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

    /// Язык ответа модели — по языку интерфейса приложения.
    static var responseLanguageInstruction: String {
        switch Locale.current.language.languageCode?.identifier {
        case "en": "Отвечай на английском языке."
        case "kk": "Отвечай на казахском языке."
        default: "Отвечай на русском языке."
        }
    }

    private static func unavailabilityMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(.deviceNotEligible):
            return String(localized: "Это устройство не поддерживает Apple Intelligence — показана обычная сводка.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Apple Intelligence выключен. Включите его в Настройках, чтобы получать AI-сводку.")
        case .unavailable(.modelNotReady):
            return String(localized: "Локальная модель ещё загружается. Попробуйте чуть позже.")
        case .unavailable:
            return String(localized: "Локальная модель сейчас недоступна — показана обычная сводка.")
        }
    }

    // MARK: - Подготовка контекста (вызывается на главном акторе)

    static func contextDescription(
        tasks: [TaskItem],
        habits: [Habit],
        transactions: [MoneyTransaction] = [],
        steps: Int? = nil,
        sleepHours: Double? = nil,
        subscriptions: [Subscription] = [],
        focusSessions: [FocusSession] = [],
        moods: [MoodEntry] = []
    ) -> String {
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

        lines.append("\nЗдоровье:")
        if let steps {
            lines.append("- шагов сегодня: \(steps)")
        }
        if let sleepHours, sleepHours > 0 {
            lines.append("- сон прошлой ночью: \(String(format: "%.1f", sleepHours)) ч.")
        }
        if steps == nil && (sleepHours ?? 0) == 0 {
            lines.append("- данных нет")
        }

        let monthTransactions = transactions.filter {
            Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
        }
        if monthTransactions.isEmpty {
            lines.append("\nФинансы за текущий месяц: данных нет.")
        } else {
            let income = monthTransactions.filter { !$0.isExpense }.reduce(Decimal(0)) { $0 + $1.amount }
            let expenses = monthTransactions.filter(\.isExpense).reduce(Decimal(0)) { $0 + $1.amount }
            lines.append("\nФинансы за текущий месяц: доходы \(income.asCurrency), расходы \(expenses.asCurrency).")
            let grouped = Dictionary(grouping: monthTransactions.filter(\.isExpense), by: \.category)
                .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
            for (category, total) in grouped.sorted(by: { $0.value > $1.value }).prefix(3) {
                lines.append("- \(category): \(total.asCurrency)")
            }
        }

        let activeSubscriptions = subscriptions.filter(\.isActive)
        if !activeSubscriptions.isEmpty {
            let monthly = activeSubscriptions.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
            lines.append("\nПодписки: \(activeSubscriptions.count) шт., ~\(monthly.asCurrency) в месяц.")
            for subscription in activeSubscriptions.filter(\.chargesTomorrow) {
                lines.append("- ВАЖНО: завтра спишется \(subscription.amount.asCurrency) за \(subscription.name).")
            }
        }

        let todayFocus = focusSessions.filter { Calendar.current.isDateInToday($0.startedAt) }
        if !todayFocus.isEmpty {
            let minutes = todayFocus.reduce(0) { $0 + $1.minutes }
            let labels = Set(todayFocus.map(\.label).filter { !$0.isEmpty }).joined(separator: ", ")
            lines.append("\nФокус-работа сегодня: \(minutes) мин." + (labels.isEmpty ? "" : " Над: \(labels)."))
        }

        if let todayMood = moods.first(where: { Calendar.current.isDateInToday($0.date) }) {
            var moodLine = "\nНастроение сегодня: \(todayMood.emoji) (\(todayMood.score)/5)"
            if !todayMood.note.isEmpty { moodLine += ", комментарий: \(todayMood.note)" }
            lines.append(moodLine + ".")
        }

        return lines.joined(separator: "\n")
    }

    static func ruleBasedSummary(
        tasks: [TaskItem],
        habits: [Habit],
        steps: Int? = nil,
        sleepHours: Double? = nil
    ) -> String {
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

        if let steps {
            parts.append("Шагов сегодня: \(steps).")
        }
        if let sleepHours, sleepHours > 0 {
            parts.append("Сон: \(String(format: "%.1f", sleepHours)) ч.")
        }

        return parts.joined(separator: " ")
    }
}
