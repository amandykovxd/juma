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
        case .low: "Низкий"
        case .normal: "Обычный"
        case .high: "Высокий"
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

// MARK: - Заметки (база знаний)

@Model
final class Note {
    var title: String = ""
    var content: String = ""
    /// Теги через запятую, например: "работа, идеи"
    var tags: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

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
