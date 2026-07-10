import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    enum SummaryState {
        case idle
        case generating
        case ai(DailySummary)
        case fallback(text: String, note: String)
    }

    @State private var summaryState: SummaryState = .idle

    private var todayTasks: [TaskItem] {
        tasks
            .filter { !$0.isDone && ($0.isOverdue || $0.isDueToday) }
            .sorted { $0.priorityRaw > $1.priorityRaw }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                tasksSection
                habitsSection
            }
            .navigationTitle("Сегодня")
        }
    }

    // MARK: - AI-сводка

    private var summarySection: some View {
        Section {
            switch summaryState {
            case .idle:
                Button {
                    generateSummary()
                } label: {
                    Label("Сводка дня", systemImage: "sparkles")
                }

            case .generating:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Локальная модель думает…")
                        .foregroundStyle(.secondary)
                }

            case .ai(let summary):
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI-сводка", systemImage: "sparkles")
                        .font(.headline)
                    Text(summary.overview)
                    summaryRow(icon: "target", title: "Фокус", text: summary.mainFocus)
                    summaryRow(icon: "checklist", title: "Задачи", text: summary.taskAdvice)
                    summaryRow(icon: "repeat", title: "Привычки", text: summary.habitAdvice)
                    regenerateButton
                }
                .padding(.vertical, 4)

            case .fallback(let text, let note):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Сводка дня", systemImage: "doc.text")
                        .font(.headline)
                    Text(text)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    regenerateButton
                }
                .padding(.vertical, 4)
            }
        } footer: {
            if case .idle = summaryState {
                Text("Сводка генерируется на устройстве моделью Apple Intelligence. Данные никуда не отправляются.")
            }
        }
    }

    private var regenerateButton: some View {
        Button {
            generateSummary()
        } label: {
            Label("Обновить", systemImage: "arrow.clockwise")
                .font(.subheadline)
        }
        .buttonStyle(.borderless)
    }

    private func summaryRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
            }
        }
    }

    private func generateSummary() {
        summaryState = .generating
        let context = DailySummaryService.contextDescription(tasks: tasks, habits: habits)
        let fallback = DailySummaryService.ruleBasedSummary(tasks: tasks, habits: habits)
        Task {
            let outcome = await DailySummaryService.makeSummary(context: context, fallbackText: fallback)
            switch outcome {
            case .ai(let summary):
                summaryState = .ai(summary)
            case .fallback(let text, let note):
                summaryState = .fallback(text: text, note: note)
            }
        }
    }

    // MARK: - Задачи на сегодня

    private var tasksSection: some View {
        Section("Задачи на сегодня") {
            if todayTasks.isEmpty {
                Text("Просроченных задач и задач на сегодня нет 🎉")
                    .foregroundStyle(.secondary)
            }
            ForEach(todayTasks) { task in
                TaskRowView(task: task)
            }
        }
    }

    // MARK: - Привычки

    private var habitsSection: some View {
        Section("Привычки") {
            if habits.isEmpty {
                Text("Добавьте привычки на вкладке «Привычки»")
                    .foregroundStyle(.secondary)
            }
            ForEach(habits) { habit in
                HabitTodayRow(habit: habit)
            }
        }
    }
}

/// Строка привычки на экране «Сегодня»: имя, серия и отметка за сегодня.
struct HabitTodayRow: View {
    @Environment(\.modelContext) private var modelContext
    let habit: Habit

    var body: some View {
        HStack {
            Text(habit.emoji)
            VStack(alignment: .leading) {
                Text(habit.name)
                if habit.currentStreak > 0 {
                    Text("🔥 серия: \(habit.currentStreak) дн.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                toggleToday()
            } label: {
                Image(systemName: habit.isCompleted(on: .now) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(habit.isCompleted(on: .now) ? .green : .secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleToday() {
        if let log = habit.log(on: .now) {
            modelContext.delete(log)
        } else {
            let log = HabitLog(date: .now)
            log.habit = habit
            modelContext.insert(log)
        }
    }
}
