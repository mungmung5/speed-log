import SwiftUI
import UniformTypeIdentifiers

/// 설정 탭
struct SettingsView: View {
    @EnvironmentObject private var recorder: TripRecorder
    @EnvironmentObject private var store: TripStore
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var alertText: String?

    private let stopOptions = [2, 3, 5, 10, 15]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("자동으로 주행 시작", isOn: $recorder.autoDetect)
                    Picker("멈춘 뒤 자동 종료", selection: $recorder.autoStopMinutes) {
                        Text("끔").tag(0)
                        ForEach(stopOptions, id: \.self) { minutes in
                            Text("\(minutes)분").tag(minutes)
                        }
                    }
                    Toggle("기록 중 화면 켜두기", isOn: $keepScreenOn)
                } header: {
                    Text("주행 감지")
                } footer: {
                    Text("자동 시작은 위치 권한이 '항상'이어야 해요. 차가 설정한 시간 이상 멈춰 있으면 마지막으로 움직인 시점까지 저장하고 기록을 끝내요. 신호 대기나 정체가 길다면 시간을 늘려 주세요.")
                }

                Section {
                    LabeledContent("위치 권한", value: recorder.authorizationText)
                    LabeledContent("정확한 위치", value: recorder.preciseLocation ? "켬" : "끔")
                    Button("설정 앱에서 권한 바꾸기") { SystemSettings.open() }
                } header: {
                    Text("권한")
                } footer: {
                    Text("자동 시작을 쓰려면 위치를 '항상', 정확한 위치를 '켬'으로 해 주세요. 동작 및 피트니스 권한도 허용하면 차량 이동을 더 잘 알아채요.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 단축어 앱 › 자동화 › 새로운 자동화 › 블루투스")
                        Text("2. 차 블루투스를 고르고 '연결될 때', '즉시 실행' 선택")
                        Text("3. 동작에서 Speed Log › '주행 기록 시작' 추가")
                        Text("4. 같은 방법으로 '연결 해제될 때' › '주행 기록 종료'")
                    }
                    .font(.footnote)
                    .padding(.vertical, 4)
                } header: {
                    Text("차 블루투스로 자동 시작·종료 (추천)")
                } footer: {
                    Text("차에 타서 블루투스가 연결되면 바로 기록을 시작하고, 시동을 끄면 저장해요. 가장 확실한 방법이에요.")
                }

                Section {
                    Button {
                        export { try store.exportBackup() }
                    } label: {
                        Label("전체 백업 내보내기", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        export { try store.exportCSV() }
                    } label: {
                        Label("운행 목록 엑셀(CSV)로 내보내기", systemImage: "tablecells")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("백업 불러오기", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("백업")
                } footer: {
                    Text("기록은 이 아이폰에만 저장돼요. 앱을 지우면 기록도 지워지니 가끔 백업해 두세요. '파일' 앱 › 나의 iPhone › Speed Log 폴더에서도 볼 수 있어요.")
                }

                Section("앱 정보") {
                    LabeledContent("버전", value: versionText)
                    LabeledContent("저장된 주행", value: "\(store.trips.count)개")
                }
            }
            .navigationTitle("설정")
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let added = try store.importBackup(from: url)
                        alertText = added > 0 ? "\(added)개의 주행을 불러왔어요." : "새로 불러올 주행이 없어요."
                    } catch {
                        alertText = "백업 파일을 읽지 못했어요."
                    }
                case .failure:
                    alertText = "파일을 열지 못했어요."
                }
            }
            .alert(
                alertText ?? "",
                isPresented: Binding(
                    get: { alertText != nil },
                    set: { if !$0 { alertText = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            }
        }
    }

    private func export(_ make: () throws -> URL) {
        do {
            shareItem = ShareItem(url: try make())
        } catch {
            alertText = "파일을 만들지 못했어요."
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (빌드 \(build))"
    }
}
