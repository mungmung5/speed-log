import Foundation

/// 사용자가 동의하거나 철회한 기록 (언제, 어떤 내용에)
struct ConsentRecord: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case age14, privacy, communityRules, locationSharing
    }

    var id: UUID
    var kind: Kind
    var agreed: Bool
    var date: Date
    var version: String

    var title: String {
        switch kind {
        case .age14: return "만 14세 이상 확인"
        case .privacy: return "개인정보 수집·이용"
        case .communityRules: return "신고·차단과 이용 규칙"
        case .locationSharing: return "주행 기록(위치) 공유"
        }
    }
}

struct BlockedUser: Codable, Identifiable, Hashable {
    var id: String
    var nickname: String
    var date: Date
}

struct Account: Codable {
    var id: UUID
    var nickname: String
    var createdAt: Date
    var shareTrips: Bool        // 주행 기록 공유 (기본 꺼짐)
    var hideEnds: Bool          // 출발·도착 주변 가리기 (기본 켜짐)
    var hideRadius: Int         // 가릴 범위(m)
    var consents: [ConsentRecord]
    var blocked: [BlockedUser]
}

/// 계정과 공유 설정 (지금은 이 폰에 저장, 서버를 붙이면 함께 반영)
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    /// 동의 내용이 바뀌면 이 값을 올려 다시 동의를 받음
    static let termsVersion = "2026-10-25"
    static let radiusOptions = [200, 500, 1000]

    @Published private(set) var account: Account?

    private let fileURL: URL

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("SpeedLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("account.json")
        if let data = try? Data(contentsOf: fileURL) {
            account = try? Self.decoder.decode(Account.self, from: data)
        }
    }

    private func save() {
        guard let account, let data = try? Self.encoder.encode(account) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func record(_ kind: ConsentRecord.Kind, _ agreed: Bool) -> ConsentRecord {
        ConsentRecord(id: UUID(), kind: kind, agreed: agreed, date: Date(), version: Self.termsVersion)
    }

    // MARK: - 만들기

    static func isValidNickname(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...12).contains(trimmed.count)
    }

    func create(nickname: String, shareTrips: Bool, hideEnds: Bool, hideRadius: Int) {
        account = Account(
            id: UUID(),
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            shareTrips: shareTrips,
            hideEnds: hideEnds,
            hideRadius: hideRadius,
            consents: [
                record(.age14, true),
                record(.privacy, true),
                record(.communityRules, true),
                record(.locationSharing, shareTrips)
            ],
            blocked: []
        )
        save()
    }

    // MARK: - 설정 바꾸기

    func setSharing(_ on: Bool) {
        guard account != nil, account?.shareTrips != on else { return }
        account?.shareTrips = on
        account?.consents.append(record(.locationSharing, on))
        save()
    }

    func setHideEnds(_ on: Bool) {
        account?.hideEnds = on
        save()
    }

    func setHideRadius(_ meters: Int) {
        account?.hideRadius = meters
        save()
    }

    func unblock(_ user: BlockedUser) {
        account?.blocked.removeAll { $0.id == user.id }
        save()
    }

    // MARK: - 탈퇴

    /// 계정을 지움. 서버를 붙이면 서버의 계정·공유 기록·채팅도 함께 삭제
    func deleteAccount(alsoDeleteTrips: Bool) {
        if alsoDeleteTrips {
            TripStore.shared.deleteAll()
        }
        try? FileManager.default.removeItem(at: fileURL)
        account = nil
    }
}

/// 공유할 때 집·회사 위치가 드러나지 않도록 출발·도착 주변을 지움
enum PrivacyZone {
    static func trim(_ points: [TrackPoint], radius: Double) -> [TrackPoint] {
        guard radius > 0, let first = points.first, let last = points.last else { return points }
        let start = first.location
        let end = last.location
        return points.filter {
            $0.location.distance(from: start) > radius && $0.location.distance(from: end) > radius
        }
    }
}
