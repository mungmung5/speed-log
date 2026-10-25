import SwiftUI

// MARK: - 안내 화면 공통 부품

/// 단계 맨 위의 큰 아이콘과 제목
struct StepHeader: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 아이콘 + 한 줄 설명 (**굵게** 표시 가능)
struct InfoRow: View {
    let icon: String
    let text: String
    var tint: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(LocalizedStringKey(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 제목이 붙은 묶음 상자
struct InfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 눈에 띄는 강조 상자
struct Callout: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// [필수]/[선택] 체크 상자
struct CheckRow: View {
    let text: String
    var required = true
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.blue : Color.secondary)
                (Text(required ? "[필수] " : "[선택] ").foregroundColor(required ? Color.red : Color.secondary)
                    + Text(text))
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOn ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 기록 공유 켜기·끄기 상자
struct ShareToggleCard: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text("내 주행 기록 공유")
                    .font(.headline)
                Text(isOn ? "켜짐 · 켠 뒤에 기록한 주행이 공유돼요" : "꺼짐 · 내 기록은 나만 봐요")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isOn ? Color.orange : Color.secondary)
            }
        }
        .tint(.orange)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isOn ? Color.orange : Color(.separator), lineWidth: isOn ? 2 : 1)
        )
    }
}

/// 출발·도착 가리기 상자
struct HideEndsCard: View {
    @Binding var hideEnds: Bool
    @Binding var radius: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hideEnds) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("출발·도착 주변 가리기")
                        .font(.headline)
                    Text("집이나 회사 위치가 드러나지 않게, 공유할 때 처음과 끝 구간을 지도에서 지워요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hideEnds {
                Picker("가릴 범위", selection: $radius) {
                    ForEach(AccountStore.radiusOptions, id: \.self) { m in
                        Text(m >= 1000 ? "\(m / 1000)km" : "\(m)m").tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 계정 만들기 (5단계)

struct OnboardingView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var shareTrips = false
    @State private var hideEnds = true
    @State private var hideRadius = 500
    @State private var privacyAgreed = false
    @State private var rulesAgreed = false
    @State private var age14 = false
    @State private var nickname = ""

    private let lastStep = 4

    init(initialStep: Int = 0) {
        _step = State(initialValue: min(max(initialStep, 0), 4))
        if Demo.isOn && initialStep >= 4 {
            _nickname = State(initialValue: "산길러")
            _privacyAgreed = State(initialValue: true)
            _rulesAgreed = State(initialValue: true)
            _age14 = State(initialValue: true)
        }
    }

    private var nicknameValid: Bool { AccountStore.isValidNickname(nickname) }

    private var canAdvance: Bool {
        switch step {
        case 2: return privacyAgreed
        case 3: return rulesAgreed
        case lastStep: return privacyAgreed && rulesAgreed && age14 && nicknameValid
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(lastStep + 1))
                    .tint(.blue)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case 0: introStep
                        case 1: sharingStep
                        case 2: privacyStep
                        case 3: rulesStep
                        default: finishStep
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                bottomBar
            }
            .navigationTitle("계정 만들기 \(step + 1)/\(lastStep + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)
        }
        .interactiveDismissDisabled()
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !canAdvance {
                Text(hintText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Text("이전")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    advance()
                } label: {
                    Text(step == lastStep ? "이대로 계정 만들기" : "다음")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var hintText: String {
        switch step {
        case 2: return "내용을 읽고 맨 아래 체크해 주세요"
        case 3: return "규칙에 동의해야 다음으로 넘어가요"
        default:
            if !nicknameValid { return "닉네임을 2~12자로 정해 주세요" }
            return "필수 항목을 모두 체크해 주세요"
        }
    }

    private func advance() {
        if step < lastStep {
            step += 1
        } else {
            accounts.create(nickname: nickname, shareTrips: shareTrips, hideEnds: hideEnds, hideRadius: hideRadius)
            dismiss()
        }
    }

    // MARK: 1. 소개

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "person.2.fill",
                color: .blue,
                title: "함께 달리는 계정",
                subtitle: "계정을 만들면 다른 사람과 주행 기록을 나누고 이야기할 수 있어요."
            )
            InfoCard(title: "계정으로 할 수 있는 것") {
                InfoRow(icon: "map", text: "내 주행 기록 공유와 랭킹")
                InfoRow(icon: "bubble.left.and.bubble.right", text: "다른 사용자와 채팅")
            }
            InfoRow(icon: "iphone", text: "계정이 없어도 **주행 기록은 지금처럼 이 폰에서 모두** 쓸 수 있어요.", tint: .green)
            Callout(
                icon: "exclamationmark.circle.fill",
                text: "다음 화면부터 **무엇이 공유되는지, 어떻게 끄는지, 탈퇴하면 무엇이 지워지는지** 차례로 보여드려요. 꼭 읽어 주세요.",
                color: .blue
            )
        }
    }

    // MARK: 2. 기록 공유 (위치정보)

    private var sharingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "location.fill",
                color: .orange,
                title: "내 주행 기록 공유",
                subtitle: "주행 기록에는 위치가 담겨 있어서, 직접 켜야만 공유돼요."
            )
            Callout(icon: "hand.raised.fill", text: "기본값은 **공유 안 함**이에요.", color: .orange)
            InfoCard(title: "공유를 켜면 다른 사람이 볼 수 있는 것") {
                InfoRow(icon: "map", text: "주행 경로 (지도)", tint: .orange)
                InfoRow(icon: "calendar", text: "날짜와 시간", tint: .orange)
                InfoRow(icon: "speedometer", text: "거리, 속도, 커브 수, 고도", tint: .orange)
                InfoRow(icon: "person.crop.circle", text: "내 닉네임", tint: .orange)
            }
            InfoCard(title: "공유를 켜도 보이지 않는 것") {
                InfoRow(icon: "eye.slash", text: "**공유를 켜기 전**에 기록한 주행", tint: .green)
                InfoRow(icon: "location.slash", text: "**지금 내가 있는 위치** (실시간 위치는 공유하지 않아요)", tint: .green)
            }
            ShareToggleCard(isOn: $shareTrips)
            HideEndsCard(hideEnds: $hideEnds, radius: $hideRadius)
            InfoRow(
                icon: "arrow.uturn.backward.circle",
                text: "**언제든** '함께' 탭에서 끌 수 있고, 끄면 이미 공유된 기록도 **바로 내려가요**."
            )
        }
    }

    // MARK: 3. 개인정보

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "lock.shield.fill",
                color: .green,
                title: "내 정보는 이렇게 다뤄요",
                subtitle: "무엇을 모으고, 무엇을 모으지 않고, 언제 지우는지 알려드려요."
            )
            InfoCard(title: "모으는 것") {
                InfoRow(icon: "person.text.rectangle", text: "닉네임", tint: .green)
                InfoRow(icon: "map", text: "공유를 켠 뒤의 주행 기록", tint: .green)
                InfoRow(icon: "bubble.left", text: "내가 보낸 채팅", tint: .green)
                InfoRow(icon: "flag", text: "신고·차단 내역", tint: .green)
            }
            InfoCard(title: "모으지 않는 것") {
                InfoRow(icon: "xmark.circle", text: "실명, 전화번호, 주소", tint: .secondary)
                InfoRow(icon: "iphone", text: "공유하지 않은 주행 기록 (**이 폰에만** 있어요)", tint: .secondary)
            }
            InfoCard(title: "탈퇴하면") {
                InfoRow(icon: "trash", text: "계정, 공유한 기록, 보낸 채팅이 **바로 삭제**돼요.", tint: .red)
                InfoRow(icon: "iphone", text: "이 폰의 주행 기록은 **남길지 지울지** 탈퇴할 때 고를 수 있어요.", tint: .red)
            }
            Callout(
                icon: "exclamationmark.triangle.fill",
                text: "채팅이나 다른 사람의 기록을 **캡처해서 퍼뜨리면 법적 책임**이 생길 수 있어요. 다른 사람의 대화와 기록은 함부로 공유하지 마세요.",
                color: .red
            )
            CheckRow(text: "위 내용을 읽었고, 개인정보 수집·이용에 동의해요", isOn: $privacyAgreed)
        }
    }

    // MARK: 4. 신고·차단과 규칙

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "flag.fill",
                color: .red,
                title: "신고·차단과 이용 규칙",
                subtitle: "모두가 편하게 쓰도록 이렇게 운영해요."
            )
            InfoCard(title: "신고") {
                InfoRow(icon: "hand.tap", text: "메시지나 공유 기록을 **길게 눌러 신고**할 수 있어요.", tint: .red)
                InfoRow(icon: "checkmark.shield", text: "운영자가 확인한 뒤 숨기거나 이용을 제한해요.", tint: .red)
            }
            InfoCard(title: "차단") {
                InfoRow(icon: "person.crop.circle.badge.xmark", text: "차단한 사람의 메시지와 기록은 **내게 보이지 않아요**.", tint: .red)
                InfoRow(icon: "bubble.left.and.exclamationmark.bubble.right", text: "그 사람도 **내게 메시지를 보낼 수 없어요**.", tint: .red)
                InfoRow(icon: "arrow.uturn.backward", text: "'함께' 탭의 차단 목록에서 언제든 풀 수 있어요.", tint: .red)
            }
            InfoCard(title: "지켜 주세요") {
                InfoRow(icon: "nosign", text: "욕설, 괴롭힘, 다른 사람의 개인정보 올리기 금지", tint: .secondary)
                InfoRow(icon: "car", text: "**도로교통법**을 지켜 주세요. 과속·난폭운전을 자랑하는 기록은 숨겨질 수 있어요.", tint: .secondary)
            }
            CheckRow(text: "규칙을 지키고, 어기면 이용이 제한될 수 있다는 데 동의해요", isOn: $rulesAgreed)
        }
    }

    // MARK: 5. 닉네임과 최종 확인

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                icon: "checkmark.seal.fill",
                color: .blue,
                title: "마지막 확인",
                subtitle: "닉네임을 정하고, 고른 설정을 한 번 더 확인해 주세요."
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("닉네임")
                    .font(.subheadline.weight(.semibold))
                TextField("2~12자", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if !nickname.isEmpty && !nicknameValid {
                    Text("2~12자로 정해 주세요")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            CheckRow(text: "만 14세 이상이에요", isOn: $age14)
            Text("만 14세 미만은 보호자 동의가 필요해서 지금은 가입할 수 없어요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            InfoCard(title: "내가 고른 설정") {
                summaryRow("주행 기록 공유", shareTrips ? "켬" : "끔", highlight: shareTrips)
                summaryRow("출발·도착 주변 가리기", hideEnds ? "\(hideRadius)m" : "끔", highlight: !hideEnds)
                summaryRow("개인정보 수집·이용", privacyAgreed ? "동의" : "미동의", highlight: false)
                summaryRow("신고·차단과 이용 규칙", rulesAgreed ? "동의" : "미동의", highlight: false)
            }
            InfoRow(icon: "gearshape", text: "이 설정은 **'함께' 탭 › 내 계정**에서 언제든 바꿀 수 있어요.")
            Callout(
                icon: "server.rack",
                text: "기록 공유·랭킹·채팅은 서버가 준비되면 열려요. 그때 **지금 고른 설정 그대로** 동작해요.",
                color: .blue
            )
        }
    }

    private func summaryRow(_ title: String, _ value: String, highlight: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(highlight ? Color.orange : Color.primary)
        }
        .font(.subheadline)
    }
}
