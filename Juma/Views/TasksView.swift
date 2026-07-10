import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var isAddingTask = false

    private var activeTasks: [TaskItem] {
        tasks
            .filter { !$0.isDone }
            .sorted {
                if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
                return $0.priorityRaw > $1.priorityRaw
            }
    }

    private var doneTasks: [TaskItem] {
        tasks.filter(\.isDone)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Активные") {
                    if activeTasks.isEmpty {
                        Text("Нет активных задач")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activeTasks) { task in
                        TaskRowView(task: task)
                    }
                    .onDelete { offsets in
                        delete(offsets, from: activeTasks)
                    }
                }

                if !doneTasks.isEmpty {
                    Section("Выполненные") {
                        ForEach(doneTasks) { task in
                            TaskRowView(task: task)
                        }
                        .onDelete { offsets in
                            delete(offsets, from: doneTasks)
                        }
                    }
                }
            }
            .navigationTitle("Задачи")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingTask = true
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingTask) {
                TaskEditorView()
            }
        }
    }

    private func delete(_ offsets: IndexSet, from list: [TaskItem]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

/// Общая строка задачи: чекбокс, название, срок и приоритет.
struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                task.setDone(!task.isDone)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                    if task.priority == .high {
                        Label(task.priority.title, systemImage: task.priority.symbol)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Форма добавления задачи.
struct TaskEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var priority: TaskPriority = .normal
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Задача") {
                    TextField("Название", text: $title)
                    TextField("Детали (необязательно)", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Параметры") {
                    Picker("Приоритет", selection: $priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Срок выполнения", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Дата", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Новая задача")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority
        )
        modelContext.insert(task)
        dismiss()
    }
}
