import SwiftUI
import SwiftData

/// Фокус-таймер (помодоро). Сессии логируются в SwiftData и попадают в AI-сводку дня.
struct FocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]

    /// Активная сессия переживает перезапуск приложения.
    @AppStorage("focusEndDate") private var focusEndTimestamp = 0.0
    @AppStorage("focusStartDate") private var focusStartTimestamp = 0.0
    @AppStorage("focusLabel") private var focusLabel = ""

    @State private var selectedMinutes = 25
    @State private var label = ""

    private var endDate: Date? {
        focusEndTimestamp > 0 ? Date(timeIntervalSince1970: focusEndTimestamp) : nil
    }

    private var todaySessions: [FocusSession] {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    private var todayMinutes: Int {
        todaySessions.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        List {
            if let endDate, endDate > .now {
                activeSection(endDate: endDate)
            } else {
                setupSection
            }

            Section("Сегодня: \(todayMinutes) мин") {
                if todaySessions.isEmpty {
                    Text("Фокус-сессий сегодня ещё не было")
                        .foregroundStyle(.secondary)
                }
                ForEach(todaySessions) { session in
                    HStack {
                        Text(session.label.isEmpty ? String(localized: "Без названия") : session.label)
                        Spacer()
                        Text("\(session.minutes) мин")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(todaySessions[index])
                    }
                }
            }
        }
        .navigationTitle("Фокус")
        .task {
            finishIfCompleted()
        }
    }

    // MARK: - Активная сессия

    private func activeSection(endDate: Date) -> some View {
        Section {
            VStack(spacing: 12) {
                if !focusLabel.isEmpty {
                    Text(focusLabel)
                        .font(.headline)
                }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = max(0, endDate.timeIntervalSince(timeline.date))
                    Text(timeString(remaining))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .onChange(of: remaining <= 0) { _, done in
                            if done { finishIfCompleted() }
                        }
                }
                Button(role: .destructive) {
                    cancelSession()
                } label: {
                    Label("Прервать", systemImage: "xmark.circle")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Настройка новой сессии

    private var setupSection: some View {
        Section("Новая сессия") {
            Picker("Длительность", selection: $selectedMinutes) {
                Text("25 мин").tag(25)
                Text("45 мин").tag(45)
                Text("60 мин").tag(60)
            }
            .pickerStyle(.segmented)

            TextField("Над чем работаете? (необязательно)", text: $label)

            Button {
                startSession()
            } label: {
                Label("Начать фокус", systemImage: "play.circle.fill")
            }
        }
    }

    // MARK: - Логика

    private func startSession() {
        let start = Date.now
        let end = start.addingTimeInterval(TimeInterval(selectedMinutes * 60))
        focusStartTimestamp = start.timeIntervalSince1970
        focusEndTimestamp = end.timeIntervalSince1970
        focusLabel = label.trimmingCharacters(in: .whitespaces)
        Task {
            _ = await NotificationService.requestPermission()
            await NotificationService.scheduleFocusEnd(at: end, label: focusLabel)
        }
    }

    /// Если сессия дошла до конца (в том числе пока приложение было закрыто) — логируем её.
    private func finishIfCompleted() {
        guard let endDate, endDate <= .now else { return }
        let start = Date(timeIntervalSince1970: focusStartTimestamp)
        let minutes = max(1, Int(endDate.timeIntervalSince(start) / 60))
        let session = FocusSession(startedAt: start, minutes: minutes, label: focusLabel)
        modelContext.insert(session)
        resetActive()
    }

    private func cancelSession() {
        NotificationService.cancelFocusEnd()
        resetActive()
    }

    private func resetActive() {
        focusEndTimestamp = 0
        focusStartTimestamp = 0
        focusLabel = ""
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
