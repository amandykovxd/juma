import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FinancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]

    @State private var isAddingTransaction = false
    @State private var isImportingCSV = false
    @State private var importMessage: String?

    private var monthTransactions: [MoneyTransaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private var monthIncome: Decimal {
        monthTransactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var monthExpenses: Decimal {
        monthTransactions.filter(\.isExpense).reduce(0) { $0 + $1.amount }
    }

    /// Топ категорий расходов текущего месяца.
    private var topExpenseCategories: [(category: String, total: Decimal)] {
        let expenses = monthTransactions.filter(\.isExpense)
        let grouped = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (category: $0.key, total: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                monthSection

                if !topExpenseCategories.isEmpty {
                    categoriesSection
                }

                transactionsSection
            }
            .navigationTitle("Финансы")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isImportingCSV = true
                    } label: {
                        Label("Импорт CSV", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingTransaction = true
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingTransaction) {
                TransactionEditorView()
            }
            .fileImporter(
                isPresented: $isImportingCSV,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleImport(result)
            }
            .alert("Импорт CSV", isPresented: .init(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("Ок", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: - Секции

    private var monthSection: some View {
        Section(Date.now.formatted(.dateTime.month(.wide).year())) {
            LabeledContent("Доходы") {
                Text(monthIncome.asCurrency)
                    .foregroundStyle(.green)
            }
            LabeledContent("Расходы") {
                Text(monthExpenses.asCurrency)
                    .foregroundStyle(.red)
            }
            LabeledContent("Баланс") {
                Text((monthIncome - monthExpenses).asCurrency)
                    .fontWeight(.semibold)
            }
        }
    }

    private var categoriesSection: some View {
        Section("Куда уходят деньги") {
            ForEach(topExpenseCategories, id: \.category) { item in
                LabeledContent(item.category) {
                    Text(item.total.asCurrency)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transactionsSection: some View {
        Section("Операции") {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "Операций пока нет",
                    systemImage: "banknote",
                    description: Text("Добавьте первую операцию кнопкой «+» или импортируйте CSV из банка.")
                )
            }
            ForEach(transactions) { transaction in
                TransactionRowView(transaction: transaction)
            }
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(transactions[index])
                }
            }
        }
    }

    // MARK: - Импорт CSV

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = "Не удалось открыть файл: \(error.localizedDescription)"
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let imported = CSVImporter.parse(content)
                for transaction in imported {
                    modelContext.insert(transaction)
                }
                importMessage = imported.isEmpty
                    ? "В файле не нашлось операций. Формат строк: дата, сумма, категория, заметка (отрицательная сумма — расход)."
                    : "Импортировано операций: \(imported.count)."
            } catch {
                importMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        }
    }
}

struct TransactionRowView: View {
    let transaction: MoneyTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.category.isEmpty ? "Без категории" : transaction.category)
                HStack(spacing: 6) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    if !transaction.note.isEmpty {
                        Text("· \(transaction.note)")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text((transaction.isExpense ? "−" : "+") + transaction.amount.asCurrency)
                .foregroundStyle(transaction.isExpense ? .primary : Color.green)
                .fontWeight(.medium)
        }
    }
}

/// Форма добавления операции.
struct TransactionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isExpense = true
    @State private var amountText = ""
    @State private var category = TransactionCategories.expense[0]
    @State private var note = ""
    @State private var date = Date()

    private var categories: [String] {
        isExpense ? TransactionCategories.expense : TransactionCategories.income
    }

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
                    Picker("Тип", selection: $isExpense) {
                        Text("Расход").tag(true)
                        Text("Доход").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isExpense) {
                        category = categories[0]
                    }

                    TextField("Сумма", text: $amountText)
                        .keyboardType(.decimalPad)

                    Picker("Категория", selection: $category) {
                        ForEach(categories, id: \.self) { candidate in
                            Text(candidate).tag(candidate)
                        }
                    }

                    TextField("Заметка (необязательно)", text: $note)

                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Новая операция")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(parsedAmount == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let transaction = MoneyTransaction(
            amount: amount,
            isExpense: isExpense,
            category: category,
            note: note.trimmingCharacters(in: .whitespaces),
            date: date
        )
        modelContext.insert(transaction)
        dismiss()
    }
}

// MARK: - Парсер CSV

enum CSVImporter {
    /// Формат строки: `дата, сумма, категория, заметка`.
    /// Разделитель — запятая или точка с запятой. Отрицательная сумма — расход.
    /// Даты: 2026-07-10, 10.07.2026 или 10/07/2026.
    static func parse(_ content: String) -> [MoneyTransaction] {
        var result: [MoneyTransaction] = []

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let separator: Character = line.contains(";") ? ";" : ","
            let fields = line.split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard fields.count >= 2 else { continue }

            guard let date = parseDate(fields[0]) else { continue } // пропускаем заголовок
            let normalizedAmount = fields[1]
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
            guard let amount = Decimal(string: normalizedAmount), amount != 0 else { continue }

            let category = fields.count > 2 ? fields[2] : "📦 Другое"
            let note = fields.count > 3 ? fields[3] : ""

            result.append(MoneyTransaction(
                amount: abs(amount),
                isExpense: amount < 0,
                category: category.isEmpty ? "📦 Другое" : category,
                note: note,
                date: date
            ))
        }

        return result
    }

    private static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
