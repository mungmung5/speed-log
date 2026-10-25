import Foundation
import UIKit
import UserNotifications

/// 갱신 알림 식별자
let renewalNotificationID = "renewal-reminder"

/// 무료 Apple ID로 설치한 앱은 7일 뒤 만료됨.
/// 만료 시각을 읽어 하루 전에 알려주고, SideStore 갱신 단축어를 바로 실행.
@MainActor
final class RenewalHelper: ObservableObject {
    static let shared = RenewalHelper()

    /// 앱 서명이 끝나는 시각 (알 수 없으면 nil)
    @Published private(set) var expiration: Date?

    /// 만료 하루 전 알림 켜기
    @Published var remindersOn: Bool {
        didSet {
            UserDefaults.standard.set(remindersOn, forKey: Keys.reminders)
            schedule()
        }
    }

    /// 갱신할 때 실행할 단축어 이름
    @Published var shortcutName: String {
        didSet { UserDefaults.standard.set(shortcutName, forKey: Keys.shortcut) }
    }

    static let defaultShortcutName = "SideStore 갱신"

    private enum Keys {
        static let reminders = "renewalReminders"
        static let shortcut = "renewalShortcut"
    }

    private init() {
        let defaults = UserDefaults.standard
        _remindersOn = Published(initialValue: defaults.object(forKey: Keys.reminders) as? Bool ?? true)
        _shortcutName = Published(initialValue: defaults.string(forKey: Keys.shortcut) ?? Self.defaultShortcutName)
        _expiration = Published(initialValue: Self.readExpiration())
    }

    // MARK: - 상태

    var secondsLeft: TimeInterval? { expiration?.timeIntervalSinceNow }

    /// 남은 기간을 사람이 읽기 쉽게
    var remainingText: String {
        guard let s = secondsLeft else { return "확인할 수 없음" }
        if s <= 0 { return "만료됨" }
        let days = Int(s / 86_400)
        let hours = Int(s.truncatingRemainder(dividingBy: 86_400) / 3_600)
        return days > 0 ? "\(days)일 \(hours)시간" : "\(hours)시간"
    }

    /// 2일 안에 만료되면 갱신 안내
    var needsRenewalSoon: Bool {
        guard let s = secondsLeft else { return false }
        return s < 2 * 86_400
    }

    /// 앱이 열릴 때마다 만료 시각을 다시 읽고 알림을 다시 예약 (갱신하면 만료일이 늘어나 있음)
    func refresh() {
        expiration = Self.readExpiration()
        schedule()
    }

    // MARK: - 갱신 실행

    /// SideStore 갱신 단축어 실행
    func openRefreshShortcut() {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: shortcutName.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    /// 알림을 눌렀을 때
    func handleReminderTap() {
        refresh()
        // 갱신 중에는 앱이 다시 설치되며 꺼지므로, 주행 기록 중이면 실행하지 않음
        guard needsRenewalSoon, !TripRecorder.shared.isRecording else { return }
        openRefreshShortcut()
    }

    // MARK: - 알림 예약

    func schedule() {
        Task { await scheduleNow() }
    }

    private func scheduleNow() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [renewalNotificationID])
        guard remindersOn,
              let exp = expiration,
              let fireDate = Self.reminderDate(before: exp),
              fireDate > Date() else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Speed Log 갱신이 필요해요"
        content.body = "내일 앱 사용 기간이 끝나요. 눌러서 바로 갱신하세요."
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: renewalNotificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// 만료 24시간 전. 밤늦게나 새벽이면 그 전 저녁 8시로 당김
    static func reminderDate(before expiration: Date) -> Date? {
        let calendar = Calendar.current
        let target = expiration.addingTimeInterval(-24 * 3_600)
        let hour = calendar.component(.hour, from: target)
        guard hour < 9 || hour >= 21 else { return target }
        let day = hour < 9 ? calendar.date(byAdding: .day, value: -1, to: target) : target
        guard let day else { return target }
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)
    }

    // MARK: - 서명 만료일 읽기

    /// 앱 안의 embedded.mobileprovision에서 만료 시각을 읽음
    static func readExpiration() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }
}
