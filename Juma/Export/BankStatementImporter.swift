import Foundation
import PDFKit

/// Импорт PDF-выписки Kaspi (Kaspi Gold → «Выписка» → PDF).
/// У Kaspi и Halyk нет публичных API для личных счетов, поэтому работаем с выпиской.
/// Формат строки операции: `03.07.25  - 12 500,00 ₸  Покупка  Magnum`.
enum KaspiStatementImporter {

    static func parse(pdfURL: URL) -> [MoneyTransaction] {
        guard let document = PDFDocument(url: pdfURL) else { return [] }
        var text = ""
        for pageIndex in 0..<document.pageCount {
            text += (document.page(at: pageIndex)?.string ?? "") + "\n"
        }
        return parse(text: text)
    }

    static func parse(text: String) -> [MoneyTransaction] {
        text.split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> MoneyTransaction? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 3, let date = DateParsing.parse(tokens[0]) else { return nil }

        // Собираем сумму до токена с «₸» (сумма бывает разбита пробелами: «- 12 500,00 ₸»).
        var amountPart = ""
        var index = 1
        var foundCurrency = false
        while index < tokens.count {
            let token = tokens[index]
            amountPart += token
            index += 1
            if token.contains("₸") {
                foundCurrency = true
                break
            }
        }
        guard foundCurrency else { return nil }

        let minusSigns = ["-", "−", "–"]
        let isExpense = minusSigns.contains(where: amountPart.hasPrefix) || !amountPart.hasPrefix("+")

        var cleaned = amountPart
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: ",", with: ".")
        for symbol in minusSigns + ["+", "\u{00A0}", "\u{202F}", " "] {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }
        guard let amount = Decimal(string: cleaned), amount > 0 else { return nil }

        let operation = index < tokens.count ? tokens[index] : ""
        let details = tokens.dropFirst(index + 1).joined(separator: " ")

        return MoneyTransaction(
            amount: amount,
            isExpense: isExpense,
            category: category(for: operation),
            note: details,
            date: date
        )
    }

    private static func category(for operation: String) -> String {
        let lowered = operation.lowercased()
        if lowered.contains("покупк") { return "🛍 Покупки" }
        if lowered.contains("перевод") { return "🔁 Перевод" }
        if lowered.contains("пополнен") { return "➕ Пополнение" }
        if lowered.contains("снят") { return "🏧 Снятие" }
        if lowered.contains("платеж") || lowered.contains("платёж") { return "📱 Подписки" }
        return "📦 Другое"
    }
}

/// Общий парсер дат для CSV и банковских выписок.
enum DateParsing {
    /// Понимает 2026-07-10, 10.07.2026, 10/07/2026 и 03.07.25.
    static func parse(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "dd.MM.yy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                // Отсекаем ложные срабатывания вроде «25» → 25-й год н.э.
                let year = Calendar.current.component(.year, from: date)
                if year >= 2000 && year <= 2100 {
                    return date
                }
            }
        }
        return nil
    }
}
