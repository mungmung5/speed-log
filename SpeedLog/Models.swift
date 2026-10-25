import Foundation
import CoreLocation

/// GPS로 받은 위치 한 점
struct TrackPoint: Codable, Hashable {
    var t: Date          // 시각
    var lat: Double
    var lon: Double
    var speed: Double    // m/s, 측정 불가면 -1
    var acc: Double      // 수평 오차(m)

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
    var speedKmh: Double { max(speed, 0) * 3.6 }
}

/// 저장된 한 번의 운행
struct Trip: Codable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var distance: Double           // m
    var maxSpeed: Double           // m/s
    var movingTime: TimeInterval   // 정차 시간을 뺀 주행 시간(초)
    var maxSpeedAt: Date?
    var startName: String?
    var endName: String?
    var autoStarted: Bool?

    /// 출발부터 도착까지 걸린 시간
    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
    /// 평균 속도(정차 포함), m/s
    var averageSpeed: Double { duration > 0 ? distance / duration : 0 }
    /// 정차를 뺀 평균 속도, m/s
    var movingAverageSpeed: Double { movingTime > 0 ? distance / movingTime : 0 }

    var routeTitle: String {
        "\(startName ?? "출발지") → \(endName ?? "도착지")"
    }
}

/// 기록 중인 운행을 앱이 종료돼도 이어갈 수 있게 저장하는 임시 데이터
struct ActiveTripSnapshot: Codable {
    var id: UUID
    var start: Date
    var autoStarted: Bool
    var points: [TrackPoint]
}

/// 백업 파일 형식
struct Backup: Codable {
    var version: Int
    var exportedAt: Date
    var trips: [BackupTrip]
}

struct BackupTrip: Codable {
    var trip: Trip
    var points: [TrackPoint]
}

/// 위치 점을 받아 거리·최고속도·주행시간을 누적 계산
struct TripAccumulator {
    static let maxAccuracy: Double = 30          // m, 이보다 부정확한 위치는 버림
    static let speedAccuracyLimit: Double = 2.5  // m/s, 속도 오차가 이보다 크면 최고속도에 반영 안 함
    static let movingSpeed: Double = 1.4         // m/s ≈ 5 km/h 이상이면 움직이는 중
    static let maxPlausibleSpeed: Double = 90    // m/s ≈ 324 km/h 넘는 값은 오류로 봄

    private(set) var distance: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var maxSpeedAt: Date?
    private(set) var movingTime: TimeInterval = 0
    private(set) var lastMovingAt: Date?
    private var last: TrackPoint?

    /// 점을 반영하고, 경로에 저장할 점이면 true를 돌려줌
    mutating func add(_ p: TrackPoint, speedAccuracy: Double? = nil) -> Bool {
        guard p.acc >= 0, p.acc <= Self.maxAccuracy else { return false }

        var segment: Double = 0
        var interval: TimeInterval = 0
        let hasPrevious = last != nil
        if let prev = last {
            interval = p.t.timeIntervalSince(prev.t)
            guard interval > 0 else { return false }
            segment = prev.location.distance(from: p.location)
            // 순간이동처럼 튀는 점은 버림
            guard segment / interval <= Self.maxPlausibleSpeed else { return false }
        }

        let speed: Double
        if p.speed >= 0 {
            speed = p.speed
        } else {
            speed = interval > 0 ? segment / interval : 0
        }
        let moving = speed >= Self.movingSpeed

        // 정차 중 GPS 흔들림은 거리에 넣지 않음
        if hasPrevious, !moving, segment < max(p.acc, 8) { return false }

        if p.speed >= 0, p.speed <= Self.maxPlausibleSpeed {
            let trusted: Bool
            if let sa = speedAccuracy, sa >= 0 {
                trusted = sa <= Self.speedAccuracyLimit
            } else {
                trusted = p.acc <= 15
            }
            if trusted, p.speed > maxSpeed {
                maxSpeed = p.speed
                maxSpeedAt = p.t
            }
        }

        if moving {
            if hasPrevious { movingTime += min(interval, 15) }
            lastMovingAt = p.t
        }
        distance += segment
        last = p
        return true
    }
}
