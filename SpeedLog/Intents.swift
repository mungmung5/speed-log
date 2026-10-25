import AppIntents

/// 단축어: 주행 기록 시작 (차 블루투스 연결 자동화용)
struct StartTripIntent: AppIntent {
    static var title: LocalizedStringResource = "주행 기록 시작"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = TripRecorder.shared
        if recorder.isRecording {
            return .result(dialog: "이미 주행을 기록하고 있어요.")
        }
        recorder.start()
        if recorder.isRecording {
            return .result(dialog: "주행 기록을 시작했어요.")
        }
        return .result(dialog: "위치 권한을 확인해 주세요.")
    }
}

/// 단축어: 주행 기록 종료 (차 블루투스 해제 자동화용)
struct StopTripIntent: AppIntent {
    static var title: LocalizedStringResource = "주행 기록 종료"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = TripRecorder.shared
        guard recorder.isRecording else {
            return .result(dialog: "기록 중인 주행이 없어요.")
        }
        recorder.stop()
        return .result(dialog: "주행 기록을 저장했어요.")
    }
}

struct SpeedLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripIntent(),
            phrases: [
                "\(.applicationName) 주행 시작",
                "\(.applicationName) 기록 시작"
            ],
            shortTitle: "주행 시작",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: StopTripIntent(),
            phrases: [
                "\(.applicationName) 주행 종료",
                "\(.applicationName) 기록 종료"
            ],
            shortTitle: "주행 종료",
            systemImageName: "stop.circle.fill"
        )
    }
}
