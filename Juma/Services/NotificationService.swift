import Foundation
import UserNotifications

/// Локальные уведомления: напоминания о списаниях подписок и конец фокус-сессии.
enum NotificationService {

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Уведомление за день до списания подписки, в 10:00.
    static func scheduleChargeReminder(for subscription: Subscription) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [subscription.notificationID])
        guard subscription.isActive else { return }

        let calendar = Calendar.current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: subscription.nextChargeDate) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        components.hour = 10

        guard let fireDate = calendar.date(from: components), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Завтра списание")
        content.body = String(localized: "Завтра спишется \(subscription.amount.asCurrency) за \(subscription.name).")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: subscription.notificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelChargeReminder(for subscription: Subscription) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [subscription.notificationID])
    }

    /// Уведомление об окончании фокус-сессии.
    static func scheduleFocusEnd(at date: Date, label: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["focus-end"])
        guard date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Фокус-сессия завершена")
        content.body = label.isEmpty
            ? String(localized: "Отличная работа! Сделайте перерыв.")
            : String(localized: "Отличная работа над «\(label)»! Сделайте перерыв.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: "focus-end", content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelFocusEnd() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["focus-end"])
    }
}
