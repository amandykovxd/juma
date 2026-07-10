import SwiftUI
import SwiftData

/// CRM: контакты из телефонной книги и LinkedIn, детекция смены работы.
struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]

    @State private var searchText = ""
    @State private var isImportingLinkedIn = false
    @State private var importMessage: String?
    @State private var selectedContact: Contact?

    private var filteredContacts: [Contact] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return contacts }
        return contacts.filter {
            $0.fullName.localizedCaseInsensitiveContains(query)
                || $0.company.localizedCaseInsensitiveContains(query)
                || $0.position.localizedCaseInsensitiveContains(query)
        }
    }

    private var jobChangers: [Contact] {
        contacts.filter(\.hasRecentJobChange)
    }

    var body: some View {
        List {
            if !jobChangers.isEmpty {
                Section("Сменили работу") {
                    ForEach(jobChangers) { contact in
                        Button {
                            selectedContact = contact
                        } label: {
                            ContactRowView(contact: contact)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Все контакты (\(contacts.count))") {
                if contacts.isEmpty {
                    ContentUnavailableView(
                        "Контактов нет",
                        systemImage: "person.2",
                        description: Text("Импортируйте телефонную книгу или LinkedIn (Настройки → Get a copy of your data → Connections → CSV).")
                    )
                }
                ForEach(filteredContacts) { contact in
                    Button {
                        selectedContact = contact
                    } label: {
                        ContactRowView(contact: contact)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(filteredContacts[index])
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Имя, компания, должность")
        .navigationTitle("Люди")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        importPhoneBook()
                    } label: {
                        Label("Из телефонной книги", systemImage: "iphone")
                    }
                    Button {
                        isImportingLinkedIn = true
                    } label: {
                        Label("LinkedIn CSV", systemImage: "briefcase")
                    }
                } label: {
                    Label("Импорт", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingLinkedIn,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleLinkedInImport(result)
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
        }
        .alert("Импорт", isPresented: .init(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func importPhoneBook() {
        Task {
            do {
                let result = try await ContactImportService.importFromPhoneBook(into: modelContext, existing: contacts)
                importMessage = summary(result)
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func handleLinkedInImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = String(localized: "Не удалось открыть файл: \(error.localizedDescription)")
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let result = ContactImportService.importLinkedInCSV(content, into: modelContext, existing: contacts)
                importMessage = summary(result)
            } catch {
                importMessage = String(localized: "Не удалось прочитать файл: \(error.localizedDescription)")
            }
        }
    }

    private func summary(_ result: ContactImportService.ImportResult) -> String {
        var parts = [String(localized: "Добавлено: \(result.added), обновлено: \(result.updated).")]
        if result.jobChanges > 0 {
            parts.append(String(localized: "Обнаружено смен работы: \(result.jobChanges)!"))
        }
        return parts.joined(separator: " ")
    }
}

struct ContactRowView: View {
    let contact: Contact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.fullName)
                    if contact.hasRecentJobChange {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !contact.company.isEmpty || !contact.position.isEmpty {
                    Text([contact.position, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if contact.source == "linkedin" {
                Image(systemName: "briefcase.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ContactDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var contact: Contact

    var body: some View {
        NavigationStack {
            Form {
                Section("Контакт") {
                    LabeledContent("Имя", value: contact.fullName)
                    if !contact.company.isEmpty {
                        LabeledContent("Компания", value: contact.company)
                    }
                    if !contact.position.isEmpty {
                        LabeledContent("Должность", value: contact.position)
                    }
                    if !contact.phone.isEmpty {
                        LabeledContent("Телефон", value: contact.phone)
                    }
                    if !contact.email.isEmpty {
                        LabeledContent("Почта", value: contact.email)
                    }
                    if !contact.linkedInURL.isEmpty, let url = URL(string: contact.linkedInURL) {
                        Link("Профиль LinkedIn", destination: url)
                    }
                }

                if !contact.careerHistory.isEmpty {
                    Section("История карьеры") {
                        Text(contact.careerHistory)
                            .font(.subheadline)
                    }
                }

                Section("Мои заметки") {
                    TextEditor(text: $contact.notes)
                        .frame(minHeight: 100)
                }

                if contact.hasRecentJobChange {
                    Section {
                        Button("Отметить смену работы просмотренной") {
                            contact.hasRecentJobChange = false
                        }
                    }
                }
            }
            .navigationTitle(contact.fullName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
