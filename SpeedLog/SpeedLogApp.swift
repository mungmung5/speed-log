import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 위치 변화로 백그라운드에서 깨어났을 때도 기록기를 바로 준비
        _ = TripRecorder.shared
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// 앱을 보고 있을 때도 알림을 배너로 표시
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// 갱신 알림을 누르면 갱신 단축어 실행
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isRenewal = response.notification.request.identifier == renewalNotificationID
        completionHandler()
        guard isRenewal else { return }
        Task { @MainActor in
            // 앱이 화면에 완전히 뜬 뒤 실행
            try? await Task.sleep(nanoseconds: 700_000_000)
            RenewalHelper.shared.handleReminderTap()
        }
    }
}

@main
struct SpeedLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(TripRecorder.shared)
                .environmentObject(TripStore.shared)
                .environmentObject(RenewalHelper.shared)
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            RecordView()
                .tabItem { Label("주행", systemImage: "speedometer") }
            TripListView()
                .tabItem { Label("기록", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("통계", systemImage: "chart.bar.xaxis") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RenewalHelper.shared.refresh() }
        }
        .onAppear { RenewalHelper.shared.refresh() }
    }
}
