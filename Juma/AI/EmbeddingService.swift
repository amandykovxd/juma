import Foundation
import NaturalLanguage

/// Локальные векторные эмбеддинги через NLContextualEmbedding (Apple, on-device).
/// Используется модель для кириллицы — оптимально для русскоязычных заметок.
final class EmbeddingService {
    static let shared = EmbeddingService()

    private var model: NLContextualEmbedding?
    private var isLoaded = false

    enum EmbeddingError: LocalizedError {
        case modelUnavailable
        case assetsUnavailable
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .modelUnavailable: String(localized: "Модель эмбеддингов недоступна на этом устройстве.")
            case .assetsUnavailable: String(localized: "Не удалось скачать модель эмбеддингов. Проверьте интернет и место на устройстве.")
            case .emptyResult: String(localized: "Не удалось построить вектор для текста.")
            }
        }
    }

    /// Загружает модель, при необходимости скачивая ассеты (один раз, ~небольшой размер).
    func prepare() async throws {
        if isLoaded { return }
        guard let model = model ?? NLContextualEmbedding(language: .russian) else {
            throw EmbeddingError.modelUnavailable
        }
        self.model = model
        if !model.hasAvailableAssets {
            let result = try await model.requestAssets()
            guard result == .available else { throw EmbeddingError.assetsUnavailable }
        }
        try model.load()
        isLoaded = true
    }

    /// Вектор текста: усреднение векторов токенов (mean pooling).
    func embed(_ text: String) throws -> [Double] {
        guard let model, isLoaded else { throw EmbeddingError.modelUnavailable }
        let trimmed = String(text.prefix(2000))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyResult
        }

        let result = try model.embeddingResult(for: trimmed, language: .russian)
        var sum = [Double](repeating: 0, count: model.dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            for (index, value) in vector.enumerated() where index < sum.count {
                sum[index] += value
            }
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { throw EmbeddingError.emptyResult }
        return sum.map { $0 / Double(tokenCount) }
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / ((normA * normB).squareRoot())
    }
}
