import Foundation
import CoreLocation

/// 화면 캡처용 예시 모드.
/// 시뮬레이터에서 실행 옵션 `-demo`를 줄 때만 켜지고, 일반 사용자에게는 절대 켜지지 않음.
enum Demo {
    static let arguments = ProcessInfo.processInfo.arguments

    static var isOn: Bool { arguments.contains("-demo") }

    static func has(_ flag: String) -> Bool { isOn && arguments.contains(flag) }

    static func value(_ key: String) -> String? {
        guard isOn, let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static var startTab: Int { Int(value("-startTab") ?? "") ?? 0 }

    // MARK: - 예시 계정

    static func sampleAccount() -> Account {
        let created = Date().addingTimeInterval(-12 * 86_400)
        func consent(_ kind: ConsentRecord.Kind) -> ConsentRecord {
            ConsentRecord(id: UUID(), kind: kind, agreed: true, date: created, version: AccountStore.termsVersion)
        }
        return Account(
            id: UUID(),
            nickname: "산길러",
            createdAt: created,
            shareTrips: true,
            hideEnds: true,
            hideRadius: 500,
            consents: [consent(.age14), consent(.privacy), consent(.communityRules), consent(.locationSharing)],
            blocked: []
        )
    }

    // MARK: - 예시 주행 기록 (한계령, 국도 44호선)

    /// 캡처 작업이 실제 도로 모양(DemoRoute.json)을 넣어주면 그걸 쓰고, 없으면 굽은 길을 계산해서 만듦
    static func routeCoordinates() -> [CLLocationCoordinate2D] {
        if let url = Bundle.main.url(forResource: "DemoRoute", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let routes = json["routes"] as? [[String: Any]],
           let geometry = routes.first?["geometry"] as? [String: Any],
           let coords = geometry["coordinates"] as? [[Double]],
           coords.count > 10 {
            return coords.compactMap { c in
                c.count >= 2 ? CLLocationCoordinate2D(latitude: c[1], longitude: c[0]) : nil
            }
        }
        return syntheticRoute()
    }

    private static func syntheticRoute() -> [CLLocationCoordinate2D] {
        let lat0 = 38.111
        let lon0 = 128.383
        let mx = cos(lat0 * .pi / 180) * 111_320
        var x = 0.0
        var y = 0.0
        var heading = 100.0
        var result: [CLLocationCoordinate2D] = []
        for i in 0..<1600 {
            let s = Double(i)
            heading += 7 * sin(s / 9) + 2.2 * sin(s / 23)
            x += 10 * sin(heading * .pi / 180)
            y += 10 * cos(heading * .pi / 180)
            result.append(CLLocationCoordinate2D(latitude: lat0 + y / 110_540, longitude: lon0 + x / mx))
        }
        return result
    }

    /// 간단한 고정 난수 (매번 같은 예시가 나오도록)
    private struct Random {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func noise(_ amplitude: Double) -> Double { (next() * 2 - 1) * amplitude }
    }

    /// 경로를 따라 1초마다 위치를 만들어 운전한 것처럼 만듦 (커브에서는 감속)
    static func drive(_ route: [CLLocationCoordinate2D], start: Date, speedScale: Double, seed: UInt64) -> [TrackPoint] {
        guard route.count > 2 else { return [] }
        let lat0 = route[0].latitude
        let mx = cos(lat0 * .pi / 180) * 111_320
        let my = 110_540.0
        let xs = route.map { ($0.longitude - route[0].longitude) * mx }
        let ys = route.map { ($0.latitude - lat0) * my }
        var cumulative = [0.0]
        for i in 1..<route.count {
            cumulative.append(cumulative[i - 1] + hypot(xs[i] - xs[i - 1], ys[i] - ys[i - 1]))
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 100 else { return [] }

        func position(_ d: Double) -> (x: Double, y: Double) {
            let target = min(max(d, 0), total)
            var lo = 0
            var hi = cumulative.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if cumulative[mid] <= target { lo = mid } else { hi = mid }
            }
            let span = cumulative[hi] - cumulative[lo]
            let f = span > 0 ? (target - cumulative[lo]) / span : 0
            return (xs[lo] + (xs[hi] - xs[lo]) * f, ys[lo] + (ys[hi] - ys[lo]) * f)
        }

        func heading(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            atan2(b.x - a.x, b.y - a.y) * 180 / .pi
        }

        // 앞뒤 40m의 방향 차이로 커브를 판단해 목표 속도를 정함
        func targetSpeed(_ d: Double) -> Double {
            let a = position(d - 40)
            let b = position(d)
            let c = position(d + 40)
            var turn = abs(heading(b, c) - heading(a, b))
            if turn > 180 { turn = 360 - turn }
            let kmh = 78 - 52 * min(1, turn / 80)
            return kmh / 3.6 * speedScale
        }

        // 고갯마루(약 1,000m)까지 올라갔다 내려오는 고도
        func elevation(_ d: Double) -> Double {
            let f = d / total
            if f < 0.55 {
                return 480 + (1004 - 480) * (0.5 - 0.5 * cos(.pi * f / 0.55))
            }
            return 1004 - (1004 - 420) * (0.5 - 0.5 * cos(.pi * (f - 0.55) / 0.45))
        }

        var random = Random(state: seed)
        var points: [TrackPoint] = []
        var d = 0.0
        var v = 6.0
        var t = 0.0
        let startElevation = elevation(0)
        while d < total {
            let target = targetSpeed(d)
            v += min(max(target - v, -2.6), 1.6)
            v = max(v, 3)
            d += v
            t += 1
            let p = position(d)
            let h = elevation(d)
            points.append(TrackPoint(
                t: start.addingTimeInterval(t),
                lat: lat0 + p.y / my,
                lon: route[0].longitude + p.x / mx,
                speed: max(0, v + random.noise(0.4)),
                acc: 4 + random.next() * 3,
                alt: h + random.noise(3),
                baro: h - startElevation + random.noise(0.3)
            ))
        }
        return points
    }

    static func makeTrips() -> [(Trip, [TrackPoint])] {
        let route = routeCoordinates()
        let reversed = Array(route.reversed())
        let calendar = Calendar.current
        let now = Date()
        let plan: [(daysAgo: Int, hour: Int, minute: Int, reverse: Bool, scale: Double)] = [
            (6, 9, 12, false, 1.0), (13, 7, 40, true, 0.95), (20, 15, 5, false, 0.9),
            (34, 10, 30, true, 1.05), (41, 6, 55, false, 0.92), (63, 16, 20, true, 0.97),
            (77, 8, 10, false, 1.0), (98, 11, 45, true, 0.9), (126, 9, 0, false, 0.95),
            (150, 14, 30, true, 1.0)
        ]

        var result: [(Trip, [TrackPoint])] = []
        for (k, p) in plan.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -p.daysAgo, to: now),
                  let start = calendar.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: day)
            else { continue }
            let raw = drive(p.reverse ? reversed : route, start: start, speedScale: p.scale, seed: UInt64(k + 7))
            var acc = TripAccumulator()
            var kept: [TrackPoint] = []
            for point in raw {
                if acc.add(point) { kept.append(point) }
            }
            guard let last = kept.last else { continue }
            var trip = Trip(
                id: UUID(),
                start: start,
                end: last.t,
                distance: acc.distance,
                maxSpeed: acc.maxSpeed,
                movingTime: acc.movingTime,
                maxSpeedAt: acc.maxSpeedAt,
                startName: p.reverse ? "양양군 서면" : "인제군 북면",
                endName: p.reverse ? "인제군 북면" : "양양군 서면",
                autoStarted: false
            )
            trip.analyze(kept)
            result.append((trip, kept))
        }
        return result
    }
}
