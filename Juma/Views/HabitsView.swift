import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var isAddingHabit = false

    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty {
                    ContentUnavailableView(
                        "Нет привычек",
                        systemImage: "repeat.circle",
                        description: Text("Добавьте первую привычку — например, «Зарядка» или «Чтение 20 минут».")
                    )
                }
                ForEach(habits) { habit in
                    HabitRowView(habit: habit)
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(habits[index])
                    }
                }
            }
            .navigationTitle("Привычки")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingHabit = true
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingHabit) {
                HabitEditorView()
            }
        }
    }
}

/// Строка привычки: имя, серия, точки за последние 7 дней и отметка за сегодня.
struct HabitRowView: View {
    @Environment(\.modelContext) private var modelContext
    let habit: Habit

    private var lastSevenDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(habit.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(habit.name)
                    if habit.currentStreak > 0 {
                        Text("🔥 \(habit.currentStreak)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(lastSevenDays, id: \.self) { day in
                        Circle()
                            .fill(habit.isCompleted(on: day) ? Color.green : Color.gray.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
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
        .padding(.vertical, 2)
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

/// Форма добавления привычки.
struct HabitEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "✅"

    private let suggestedEmoji = ["✅", "🏃", "📚", "💧", "🧘", "💪", "🌅", "✍️", "🥗", "😴"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Привычка") {
                    TextField("Название, например «Зарядка»", text: $name)
                }
                Section("Значок") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(suggestedEmoji, id: \.self) { candidate in
                            Button {
                                emoji = candidate
                            } label: {
                                Text(candidate)
                                    .font(.title2)
                                    .padding(6)
                                    .background(
                                        Circle().fill(emoji == candidate ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Новая привычка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let habit = Habit(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
        modelContext.insert(habit)
        dismiss()
    }
}
