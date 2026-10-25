import SwiftUI
import UIKit
import CoreLocation

/// 주행 탭: 현재 속도와 실시간 기록
struct RecordView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @State private var confirmStop = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                statusBar
                permissionWarning
                speedometer
                statsGrid
                Spacer(minLength: 0)
                if let message = recorder.message {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .transition(.opacity)
                }
                actionButton
            }
            .padding()
            .animation(.easeInOut, value: recorder.message)
            .navigationTitle("Speed Log")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: updateIdleTimer)
        .onChange(of: recorder.isRecording) { _, _ in updateIdleTimer() }
        .onChange(of: keepScreenOn) { _, _ in updateIdleTimer() }
        .confirmationDialog("주행을 종료할까요?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("종료하고 저장", role: .destructive) { recorder.stop() }
            Button("계속 기록", role: .cancel) {}
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && recorder.isRecording
    }

    private var statusBar: some View {
        HStack {
            if recorder.isRecording {
                Label("기록 중", systemImage: "record.circle")
                    .foregroundStyle(.red)
            } else if recorder.autoDetect {
                Label("자동 감지 대기 중", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            } else {
                Label("대기 중", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if recorder.isRecording {
                gpsIndicator
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private var gpsIndicator: some View {
        let text: String
        let color: Color
        if let acc = recorder.gpsAccuracy, acc >= 0 {
            if acc <= 10 {
                text = "GPS 좋음"; color = .green
            } else if acc <= 30 {
                text = "GPS 보통"; color = .yellow
            } else {
                text = "GPS 약함"; color = .orange
            }
        } else {
            text = "GPS 찾는 중"; color = .secondary
        }
        return Label(text, systemImage: "location.fill")
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var permissionWarning: some View {
        if recorder.authorization == .denied || recorder.authorization == .restricted {
            warningBox("위치 권한이 꺼져 있어 기록할 수 없어요.")
        } else if !recorder.preciseLocation {
            warningBox("'정확한 위치'가 꺼져 있어 속도가 부정확할 수 있어요.")
        }
    }

    private func warningBox(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
            Spacer()
            Button("설정 열기") { SystemSettings.open() }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var speedometer: some View {
        VStack(spacing: 0) {
            Text(recorder.isRecording ? Fmt.speedNumber(recorder.currentSpeed) : "–")
                .font(.system(size: 128, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("km/h")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = recorder.startDate.map { context.date.timeIntervalSince($0) } ?? 0
            let average = elapsed > 0 ? recorder.distance / elapsed : 0
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: "운행 시간", value: Fmt.clock(elapsed))
                    StatTile(title: "거리", value: Fmt.km(recorder.distance))
                }
                GridRow {
                    StatTile(title: "평균 속도", value: Fmt.kmh(average))
                    StatTile(title: "최고 속도", value: Fmt.kmh(recorder.maxSpeed))
                }
                GridRow {
                    StatTile(title: "고도", value: recorder.altitude.map(Fmt.meters) ?? "–")
                    StatTile(title: "지난 커브", value: "\(recorder.liveCurveCount)개")
                }
            }
        }
    }

    private var actionButton: some View {
        Button {
            if recorder.isRecording {
                confirmStop = true
            } else {
                recorder.start()
            }
        } label: {
            Label(
                recorder.isRecording ? "주행 종료" : "주행 시작",
                systemImage: recorder.isRecording ? "stop.fill" : "play.fill"
            )
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(recorder.isRecording ? Color.red : Color.blue)
    }
}
