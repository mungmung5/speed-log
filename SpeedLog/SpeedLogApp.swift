import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 위치 변화로 백그라운드에서 깨어났을 때도 기록기를 바로 준비
        _ = TripRecorder.shared
        return true
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
        }
    }
}

struct ContentView: View {
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
    }
}
