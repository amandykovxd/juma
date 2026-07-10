import SwiftUI
import SwiftData

/// Общий контейнер данных: его используют и приложение, и Siri-интенты.
enum AppStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: TaskItem.self, Habit.self, HabitLog.self, Note.self,
                MoneyTransaction.self, Contact.self, Subscription.self,
                FocusSession.self, MoodEntry.self
            )
        } catch {
            fatalError("Не удалось создать хранилище данных: \(error)")
        }
    }()
}

@main
struct JumaApp: App {
    @AppStorage("appearance") private var appearance = "system"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(AppStore.container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
            TasksView()
                .tabItem { Label("Задачи", systemImage: "checklist") }
            FinancesView()
                .tabItem { Label("Финансы", systemImage: "banknote") }
            NotesView()
                .tabItem { Label("Заметки", systemImage: "note.text") }
            MoreView()
                .tabItem { Label("Ещё", systemImage: "ellipsis.circle") }
        }
    }
}

/// Пятая вкладка: всё, что не влезло в таб-бар.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HabitsView()
                    } label: {
                        Label("Привычки", systemImage: "repeat.circle.fill")
                    }
                    NavigationLink {
                        PeopleView()
                    } label: {
                        Label("Люди", systemImage: "person.2.fill")
                    }
                    NavigationLink {
                        SubscriptionsView()
                    } label: {
                        Label("Подписки", systemImage: "creditcard.fill")
                    }
                    NavigationLink {
                        FocusView()
                    } label: {
                        Label("Фокус", systemImage: "timer")
                    }
                }
                Section {
                    NavigationLink {
                        ExportView(isSheet: false)
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Настройки", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("Ещё")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(AppStore.container)
}
