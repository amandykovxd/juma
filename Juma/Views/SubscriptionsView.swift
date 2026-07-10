import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subscription.nextChargeDate) private var subscriptions: [Subscription]
    @State private var isAdding = false

    private var monthlyTotal: Decimal {
        subscriptions.filter(\.isActive).reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("В месяц") {
                    Text(monthlyTotal.asCurrency)
                        .fontWeight(.semibold)
                }
            } footer: {
                Text("За день до списания придёт уведомление, а сводка дня предупредит о завтрашних платежах.")
            }

            Section("Подписки") {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        "Подписок нет",
                        systemImage: "creditcard",
                        description: Text("Добавьте Яндекс Плюс, YouTube Premium, паркинг — всё, что списывается регулярно.")
                    )
                }
                ForEach(subscriptions) { subscription in
                    SubscriptionRowView(subscription: subscription)
                }
                .onDelete { offsets in
                    for index in offsets {
                        NotificationService.cancelChargeReminder(for: subscriptions[index])
                        modelContext.delete(subscriptions[index])
                    }
                }
            }
        }
        .navigationTitle("Подписки")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            SubscriptionEditorView()
        }
        .task {
            await rollDatesForward()
        }
    }

    /// Прошедшие даты списания сдвигаем на следующий период и перепланируем уведомления.
    private func rollDatesForward() async {
        for subscription in subscriptions {
            let before = subscription.nextChargeDate
            subscription.rollForwardIfNeeded()
            if before != subscription.nextChargeDate {
                await NotificationService.scheduleChargeReminder(for: subscription)
            }
        }
    }
}

struct SubscriptionRowView: View {
    let subscription: Subscription

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                Text("Спишется \(subscription.nextChargeDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(subscription.chargesTomorrow ? .orange : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(subscription.amount.asCurrency)
                    .fontWeight(.medium)
                Text(subscription.period == .month ? String(localized: "в месяц") : String(localized: "в год"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SubscriptionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountText = ""
    @State private var period: SubscriptionPeriod = .month
    @State private var nextChargeDate = Date()

    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название, например «Яндекс Плюс»", text: $name)
                    TextField("Сумма", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Период", selection: $period) {
                        Text("Ежемесячно").tag(SubscriptionPeriod.month)
                        Text("Ежегодно").tag(SubscriptionPeriod.year)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Дата списания", selection: $nextChargeDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Новая подписка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let subscription = Subscription(
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amount,
            period: period,
            nextChargeDate: nextChargeDate
        )
        modelContext.insert(subscription)
        Task {
            _ = await NotificationService.requestPermission()
            await NotificationService.scheduleChargeReminder(for: subscription)
        }
        dismiss()
    }
}
