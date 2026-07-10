import SwiftUI
import SwiftData

@main
struct JumaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [TaskItem.self, Habit.self, HabitLog.self, Note.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
            TasksView()
                .tabItem { Label("Задачи", systemImage: "checklist") }
            HabitsView()
                .tabItem { Label("Привычки", systemImage: "repeat.circle.fill") }
            NotesView()
                .tabItem { Label("Заметки", systemImage: "note.text") }
            ExportView()
                .tabItem { Label("Экспорт", systemImage: "square.and.arrow.up") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [TaskItem.self, Habit.self, HabitLog.self, Note.self], inMemory: true)
}
