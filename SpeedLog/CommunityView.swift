import SwiftUI

/// '함께' 탭: 계정 만들기, 공유 설정, 차단, 탈퇴
struct CommunityView: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var showOnboarding = Demo.value("-onboardingStep") != nil

    var body: some View {
        NavigationStack {
            Group {
                if let account = accounts.account {
                    AccountView(account: account)
                } else {
                    welcome
                }
            }
            .navigationTitle("함께")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(initialStep: Int(Demo.value("-onboardingStep") ?? "") ?? 0)
                .environmentObject(accounts)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(
                    icon: "person.2.fill",
                    color: .blue,
                    title: "함께 달려요",
                    subtitle: "계정을 만들면 주행 기록을 나누고, 랭킹을 보고, 다른 사용자와 이야기할 수 있어요."
                )
                InfoCard(title: "계정을 만들 때 확인하는 것") {
                    InfoRow(icon: "location.fill", text: "무엇이 공유되고, 어떻게 끄는지", tint: .orange)
                    InfoRow(icon: "lock.shield.fill", text: "어떤 정보를 모으고, 탈퇴하면 무엇이 지워지는지", tint: .green)
                    InfoRow(icon: "flag.fill", text: "신고·차단과 이용 규칙", tint: .red)
                }
                InfoRow(icon: "iphone", text: "계정이 없어도 주행 기록은 지금처럼 모두 쓸 수 있어요.", tint: .green)
                Button {
                    showOnboarding = true
                } label: {
                    Text("계정 만들기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }
}

/// 계정이 있을 때: 공유 설정과 관리
struct AccountView: View {
    @EnvironmentObject private var accounts: AccountStore
    let account: Account

    @State private var confirmShareOn = false
    @State private var showDelete = false

    private var shareBinding: Binding<Bool> {
        Binding(
            get: { account.shareTrips },
            set: { newValue in
                if newValue {
                    confirmShareOn = true          // 켤 때는 한 번 더 확인
                } else {
                    accounts.setSharing(false)     // 끌 때는 바로
                }
            }
        )
    }

    private var hideEndsBinding: Binding<Bool> {
        Binding(get: { account.hideEnds }, set: { accounts.setHideEnds($0) })
    }

    private var radiusBinding: Binding<Int> {
        Binding(get: { account.hideRadius }, set: { accounts.setHideRadius($0) })
    }

    var body: some View {
        Form {
            Section("내 계정") {
                LabeledContent("닉네임", value: account.nickname)
                LabeledContent("가입일", value: Fmt.date.string(from: account.createdAt))
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: account.shareTrips ? "location.fill" : "location.slash.fill")
                        .font(.title2)
                        .foregroundStyle(account.shareTrips ? Color.orange : Color.secondary)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.shareTrips ? "공유 켜짐" : "공유 꺼짐")
                            .font(.headline)
                        Text(account.shareTrips ? "켠 뒤에 기록한 주행이 다른 사람에게 보여요" : "내 주행 기록은 나만 봐요")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Toggle("내 주행 기록 공유", isOn: shareBinding)
                    .tint(.orange)
                Toggle("출발·도착 주변 가리기", isOn: hideEndsBinding)
                if account.hideEnds {
                    Picker("가릴 범위", selection: radiusBinding) {
                        ForEach(AccountStore.radiusOptions, id: \.self) { m in
                            Text(m >= 1000 ? "\(m / 1000)km" : "\(m)m").tag(m)
                        }
                    }
                }
            } header: {
                Text("기록 공유")
            } footer: {
                Text("끄면 이미 공유된 기록도 바로 내려가요. 실시간 현재 위치는 공유하지 않아요.")
            }

            Section {
                NavigationLink {
                    BlockedListView()
                } label: {
                    LabeledContent("차단한 사용자", value: "\(account.blocked.count)명")
                }
                NavigationLink {
                    ConsentHistoryView(records: account.consents)
                } label: {
                    Text("동의 내역")
                }
            } header: {
                Text("안전과 동의")
            } footer: {
                Text("메시지나 공유 기록을 길게 눌러 신고하거나 차단할 수 있어요.")
            }

            Section {
                Button("계정 삭제 (탈퇴)", role: .destructive) { showDelete = true }
            } footer: {
                Text("기록 공유·랭킹·채팅은 서버가 준비되면 열려요. 그때 위 설정 그대로 동작해요.")
            }
        }
        .alert("주행 기록 공유를 켤까요?", isPresented: $confirmShareOn) {
            Button("공유 켜기") { accounts.setSharing(true) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이제부터 기록하는 주행의 경로, 날짜, 거리, 속도가 닉네임과 함께 다른 사람에게 보여요. 언제든 다시 끌 수 있어요.")
        }
        .sheet(isPresented: $showDelete) {
            DeleteAccountView()
                .environmentObject(accounts)
        }
    }
}

/// 동의·철회 기록
struct ConsentHistoryView: View {
    let records: [ConsentRecord]

    var body: some View {
        List(records.sorted { $0.date > $1.date }) { r in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(r.agreed ? "동의" : "철회")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(r.agreed ? Color.green : Color.red)
                }
                Text("\(Fmt.dateTime.string(from: r.date)) · 약관 버전 \(r.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("동의 내역")
    }
}

/// 차단 목록
struct BlockedListView: View {
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        Group {
            if let blocked = accounts.account?.blocked, !blocked.isEmpty {
                List(blocked) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.nickname)
                            Text(Fmt.date.string(from: user.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("차단 풀기") { accounts.unblock(user) }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                ContentUnavailableView(
                    "차단한 사용자가 없어요",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("차단하면 그 사람의 메시지와 기록이 보이지 않고, 그 사람도 내게 메시지를 보낼 수 없어요.")
                )
            }
        }
        .navigationTitle("차단한 사용자")
    }
}

/// 탈퇴: 무엇이 지워지는지 보여주고 확인
struct DeleteAccountView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var alsoDeleteTrips = false
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("바로 삭제되는 것") {
                    Label("계정과 닉네임", systemImage: "person.crop.circle.badge.xmark")
                    Label("공유한 주행 기록", systemImage: "map")
                    Label("보낸 채팅", systemImage: "bubble.left")
                    Label("동의·차단 내역", systemImage: "list.bullet.rectangle")
                }
                Section {
                    Toggle("이 폰의 주행 기록도 모두 지우기", isOn: $alsoDeleteTrips)
                        .tint(.red)
                } header: {
                    Text("이 폰의 주행 기록")
                } footer: {
                    Text(alsoDeleteTrips
                         ? "이 폰에 저장된 주행 기록이 모두 지워져요. 되돌릴 수 없어요."
                         : "이 폰의 주행 기록은 그대로 남아요. 계정 없이 계속 쓸 수 있어요.")
                }
                Section {
                    Button("탈퇴하기", role: .destructive) { confirm = true }
                }
            }
            .navigationTitle("계정 삭제")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .confirmationDialog("정말 탈퇴할까요? 되돌릴 수 없어요.", isPresented: $confirm, titleVisibility: .visible) {
                Button(alsoDeleteTrips ? "탈퇴하고 주행 기록도 지우기" : "탈퇴하기", role: .destructive) {
                    accounts.deleteAccount(alsoDeleteTrips: alsoDeleteTrips)
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            }
        }
    }
}
