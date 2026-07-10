import Foundation
import HealthKit
import Observation

/// Чтение шагов и сна из HealthKit. Только чтение, только on-device.
@MainActor
@Observable
final class HealthService {
    private let store = HKHealthStore()

    private(set) var todaySteps: Int?
    private(set) var lastNightSleepHours: Double?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func connectAndLoad() async {
        guard isAvailable else {
            errorMessage = "HealthKit недоступен на этом устройстве."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let stepType = HKQuantityType(.stepCount)
        let sleepType = HKCategoryType(.sleepAnalysis)

        do {
            try await store.requestAuthorization(toShare: [], read: [stepType, sleepType])
            todaySteps = try await loadTodaySteps()
            lastNightSleepHours = try await loadLastNightSleep()
        } catch {
            errorMessage = "Не удалось получить данные Здоровья: \(error.localizedDescription)"
        }
    }

    private func loadTodaySteps() async throws -> Int {
        let stepType = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: store)
        return Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
    }

    /// Сон за прошлую ночь: окно с 18:00 вчера до текущего момента.
    private func loadLastNightSleep() async throws -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let windowStart = calendar.date(byAdding: .hour, value: -6, to: startOfToday) ?? startOfToday
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: []
        )
        let samples = try await descriptor.result(for: store)

        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds / 3600
    }
}
