import Foundation
import Contacts
import SwiftData

/// Импорт контактов из телефонной книги и LinkedIn CSV с детекцией смены работы.
enum ContactImportService {

    struct ImportResult {
        var added = 0
        var updated = 0
        var jobChanges = 0
    }

    // MARK: - Телефонная книга

    static func importFromPhoneBook(into context: ModelContext, existing: [Contact]) async throws -> ImportResult {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw NSError(domain: "Juma", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Нет доступа к контактам. Разрешите доступ в Настройках iOS.")
            ])
        }

        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]

        var fetched: [(name: String, company: String, position: String, phone: String, email: String)] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, _ in
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            fetched.append((
                name: name,
                company: contact.organizationName,
                position: contact.jobTitle,
                phone: contact.phoneNumbers.first?.value.stringValue ?? "",
                email: (contact.emailAddresses.first?.value as String?) ?? ""
            ))
        }

        var result = ImportResult()
        for item in fetched {
            if let match = findMatch(name: item.name, email: item.email, phone: item.phone, in: existing) {
                result.jobChanges += applyJobInfo(to: match, company: item.company, position: item.position)
                if match.phone.isEmpty { match.phone = item.phone }
                if match.email.isEmpty { match.email = item.email }
                result.updated += 1
            } else {
                let contact = Contact(
                    fullName: item.name,
                    company: item.company,
                    position: item.position,
                    email: item.email,
                    phone: item.phone,
                    source: "phone"
                )
                context.insert(contact)
                result.added += 1
            }
        }
        return result
    }

    // MARK: - LinkedIn CSV (Connections.csv)

    /// LinkedIn: Настройки → Get a copy of your data → Connections.
    /// Колонки: First Name, Last Name, URL, Email Address, Company, Position, Connected On.
    static func importLinkedInCSV(_ text: String, into context: ModelContext, existing: [Contact]) -> ImportResult {
        let rows = CSVDocument.parse(text)

        // Ищем строку заголовка (в начале файла бывают строки-примечания).
        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains { $0.localizedCaseInsensitiveContains("First Name") }
        }) else {
            return ImportResult()
        }
        let header = rows[headerIndex].map { $0.lowercased() }

        func column(_ name: String) -> Int? {
            header.firstIndex { $0.contains(name) }
        }
        let firstNameColumn = column("first name")
        let lastNameColumn = column("last name")
        let urlColumn = column("url")
        let emailColumn = column("email")
        let companyColumn = column("company")
        let positionColumn = column("position")

        func field(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }

        var result = ImportResult()
        for row in rows.dropFirst(headerIndex + 1) {
            let name = "\(field(row, firstNameColumn)) \(field(row, lastNameColumn))"
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let url = field(row, urlColumn)
            let email = field(row, emailColumn)
            let company = field(row, companyColumn)
            let position = field(row, positionColumn)

            let match = existing.first { !$0.linkedInURL.isEmpty && $0.linkedInURL == url }
                ?? findMatch(name: name, email: email, phone: "", in: existing)

            if let match {
                result.jobChanges += applyJobInfo(to: match, company: company, position: position)
                if match.linkedInURL.isEmpty { match.linkedInURL = url }
                if match.email.isEmpty { match.email = email }
                result.updated += 1
            } else {
                let contact = Contact(
                    fullName: name,
                    company: company,
                    position: position,
                    email: email,
                    linkedInURL: url,
                    source: "linkedin"
                )
                context.insert(contact)
                result.added += 1
            }
        }
        return result
    }

    // MARK: - Общее

    private static func findMatch(name: String, email: String, phone: String, in existing: [Contact]) -> Contact? {
        existing.first { contact in
            if !email.isEmpty && contact.email.caseInsensitiveCompare(email) == .orderedSame { return true }
            if !phone.isEmpty && !contact.phone.isEmpty && normalizePhone(contact.phone) == normalizePhone(phone) { return true }
            return contact.fullName.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func normalizePhone(_ phone: String) -> String {
        phone.filter(\.isNumber)
    }

    /// Обновляет компанию/должность; возвращает 1, если зафиксирована смена работы.
    private static func applyJobInfo(to contact: Contact, company: String, position: String) -> Int {
        var changed = 0
        let newCompany = company.trimmingCharacters(in: .whitespaces)

        if !newCompany.isEmpty && !contact.company.isEmpty
            && contact.company.caseInsensitiveCompare(newCompany) != .orderedSame {
            let date = Date.now.formatted(date: .numeric, time: .omitted)
            let from = contact.position.isEmpty ? contact.company : "\(contact.company) (\(contact.position))"
            let to = position.isEmpty ? newCompany : "\(newCompany) (\(position))"
            let line = "\(date): \(from) → \(to)"
            contact.careerHistory = contact.careerHistory.isEmpty
                ? line
                : contact.careerHistory + "\n" + line
            contact.hasRecentJobChange = true
            changed = 1
        }

        if !newCompany.isEmpty { contact.company = newCompany }
        if !position.isEmpty { contact.position = position }
        contact.updatedAt = Date()
        return changed
    }
}

/// Парсер CSV с поддержкой кавычек (в названиях компаний LinkedIn бывают запятые).
enum CSVDocument {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let character = pending {
                pending = nil
                return character
            }
            return iterator.next()
        }

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func endRow() {
            endField()
            if currentRow.contains(where: { !$0.isEmpty }) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        while let character = next() {
            if insideQuotes {
                if character == "\"" {
                    if let lookahead = next() {
                        if lookahead == "\"" {
                            currentField.append("\"") // экранированная кавычка
                        } else {
                            insideQuotes = false
                            pending = lookahead
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"" where currentField.isEmpty:
                    insideQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                case "\n":
                    endRow()
                default:
                    currentField.append(character)
                }
            }
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            endRow()
        }
        return rows
    }
}
