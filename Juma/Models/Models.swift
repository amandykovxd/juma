import Foundation
import SwiftData

// MARK: - Задачи

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: String(localized: "Низкий")
        case .normal: String(localized: "Обычный")
        case .high: String(localized: "Высокий")
        }
    }

    var symbol: String {
        switch self {
        case .low: "arrow.down.circle"
        case .normal: "minus.circle"
        case .high: "exclamationmark.circle.fill"
        }
    }
}

@Model
final class TaskItem {
    var title: String = ""
    var details: String = ""
    var dueDate: Date?
    var priorityRaw: Int = TaskPriority.normal.rawValue
    var isDone: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?

    init(title: String, details: String = "", dueDate: Date? = nil, priority: TaskPriority = .normal) {
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.createdAt = Date()
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    func setDone(_ done: Bool) {
        isDone = done
        completedAt = done ? Date() : nil
    }
}

// MARK: - Привычки

@Model
final class Habit {
    var name: String = ""
    var emoji: String = "✅"
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog] = []

    init(name: String, emoji: String = "✅") {
        self.name = name
        self.emoji = emoji
        self.createdAt = Date()
    }

    func isCompleted(on date: Date) -> Bool {
        let calendar = Calendar.current
        return logs.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func log(on date: Date) -> HabitLog? {
        let calendar = Calendar.current
        return logs.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Непрерывная серия дней. Если сегодня ещё не отмечено, серия считается от вчерашнего дня.
    var currentStreak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        if !isCompleted(on: day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while isCompleted(on: day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}

@Model
final class HabitLog {
    var date: Date = Date()
    var habit: Habit?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}

// MARK: - Финансы

@Model
final class MoneyTransaction {
    var amount: Decimal = 0
    var isExpense: Bool = true
    var category: String = ""
    var note: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()

    init(amount: Decimal, isExpense: Bool, category: String, note: String = "", date: Date = .now) {
        self.amount = amount
        self.isExpense = isExpense
        self.category = category
        self.note = note
        self.date = date
        self.createdAt = Date()
    }

    /// Со знаком: расходы отрицательные.
    var signedAmount: Decimal {
        isExpense ? -amount : amount
    }
}

enum TransactionCategories {
    static let expense = ["🛒 Продукты", "🍽 Кафе", "🚗 Транспорт", "🏠 Жильё", "💊 Здоровье", "🎬 Развлечения", "📱 Подписки", "🛍 Покупки", "📦 Другое"]
    static let income = ["💼 Зарплата", "💸 Фриланс", "🎁 Подарок", "📦 Другое"]
}

extension Decimal {
    /// Форматирование в валюте устройства (например, ₸ для Казахстана).
    var asCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }
}

// MARK: - CRM (люди)

@Model
final class Contact {
    var fullName: String = ""
    var company: String = ""
    var position: String = ""
    var email: String = ""
    var phone: String = ""
    var linkedInURL: String = ""
    /// Откуда контакт: phone | linkedin | manual
    var source: String = "manual"
    var notes: String = ""
    /// Лог смен работы, по строке на событие: «10.07.2026: Kaspi (Manager) → Halyk (Director)»
    var careerHistory: String = ""
    var hasRecentJobChange: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(fullName: String, company: String = "", position: String = "", email: String = "",
         phone: String = "", linkedInURL: String = "", source: String = "manual") {
        self.fullName = fullName
        self.company = company
        self.position = position
        self.email = email
        self.phone = phone
        self.linkedInURL = linkedInURL
        self.source = source
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Подписки

enum SubscriptionPeriod: String, CaseIterable, Identifiable {
    case month
    case year
    var id: String { rawValue }
}

@Model
final class Subscription {
    var name: String = ""
    var amount: Decimal = 0
    var periodRaw: String = SubscriptionPeriod.month.rawValue
    var nextChargeDate: Date = Date()
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(name: String, amount: Decimal, period: SubscriptionPeriod, nextChargeDate: Date) {
        self.name = name
        self.amount = amount
        self.periodRaw = period.rawValue
        self.nextChargeDate = nextChargeDate
        self.createdAt = Date()
    }

    var period: SubscriptionPeriod {
        get { SubscriptionPeriod(rawValue: periodRaw) ?? .month }
        set { periodRaw = newValue.rawValue }
    }

    var monthlyEquivalent: Decimal {
        period == .year ? amount / 12 : amount
    }

    /// Идентификатор локального уведомления.
    var notificationID: String {
        "subscription-\(persistentModelID.hashValue)"
    }

    /// Сдвигает дату списания вперёд, если она уже прошла.
    func rollForwardIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        while calendar.startOfDay(for: nextChargeDate) < today {
            let component: Calendar.Component = period == .month ? .month : .year
            guard let next = calendar.date(byAdding: component, value: 1, to: nextChargeDate) else { break }
            nextChargeDate = next
        }
    }

    var chargesTomorrow: Bool {
        Calendar.current.isDateInTomorrow(nextChargeDate)
    }
}

// MARK: - Фокус (помодоро)

@Model
final class FocusSession {
    var startedAt: Date = Date()
    var minutes: Int = 25
    var label: String = ""

    init(startedAt: Date, minutes: Int, label: String) {
        self.startedAt = startedAt
        self.minutes = minutes
        self.label = label
    }
}

// MARK: - Настроение

@Model
final class MoodEntry {
    /// Начало дня.
    var date: Date = Date()
    /// 1 (плохо) … 5 (отлично).
    var score: Int = 3
    var note: String = ""

    static let emojis = ["😞", "😕", "😐", "🙂", "😄"]

    init(date: Date, score: Int, note: String = "") {
        self.date = Calendar.current.startOfDay(for: date)
        self.score = score
        self.note = note
    }

    var emoji: String {
        Self.emojis[max(0, min(Self.emojis.count - 1, score - 1))]
    }
}

// MARK: - Заметки (база знаний)

@Model
final class Note {
    var title: String = ""
    var content: String = ""
    /// Теги через запятую, например: "работа, идеи"
    var tags: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Векторное представление заметки для семантического поиска.
    var embedding: [Double]?
    var embeddedAt: Date?

    init(title: String, content: String = "", tags: String = "") {
        self.title = title
        self.content = content
        self.tags = tags
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var tagList: [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
