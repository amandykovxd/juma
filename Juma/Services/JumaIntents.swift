import AppIntents
import Foundation
import SwiftData

/// Siri / Быстрые команды: «Добавь задачу в Juma», «Добавь расход в Juma».

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить задачу"
    static let description = IntentDescription("Добавляет новую задачу в Juma")

    @Parameter(title: "Название задачи")
    var taskTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Добавить задачу \(\.$taskTitle)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw $taskTitle.needsValueError("Как назвать задачу?")
        }
        let context = AppStore.container.mainContext
        context.insert(TaskItem(title: trimmed))
        try? context.save()
        return .result(dialog: "Задача «\(trimmed)» добавлена в Juma")
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить расход"
    static let description = IntentDescription("Записывает расход в финансы Juma")

    @Parameter(title: "Сумма")
    var amount: Double

    @Parameter(title: "На что потратили", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Добавить расход \(\.$amount) \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("Какая сумма?")
        }
        let context = AppStore.container.mainContext
        let transaction = MoneyTransaction(
            amount: Decimal(amount),
            isExpense: true,
            category: "📦 Другое",
            note: note.trimmingCharacters(in: .whitespaces)
        )
        context.insert(transaction)
        try? context.save()
        return .result(dialog: "Расход \(Decimal(amount).asCurrency) записан в Juma")
    }
}

struct JumaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Добавь задачу в \(.applicationName)",
                "Новая задача в \(.applicationName)",
                "Add a task in \(.applicationName)"
            ],
            shortTitle: "Новая задача",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Добавь расход в \(.applicationName)",
                "Запиши расход в \(.applicationName)",
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "Новый расход",
            systemImageName: "banknote"
        )
    }
}
