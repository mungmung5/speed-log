import Foundation
import CoreLocation

// MARK: - 공통 계산

enum Series {
    /// 앞뒤 radius개 값의 평균
    static func movingAverage(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0, values.count > 2 else { return values }
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for i in 0..<values.count { prefix[i + 1] = prefix[i] + values[i] }
        return values.indices.map { i in
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }

    /// 빈 값은 앞뒤 값 사이를 직선으로 채움
    static func fillGaps(_ values: [Double?]) -> [Double] {
        var result = [Double](repeating: 0, count: values.count)
        var lastIndex: Int?
        for (i, value) in values.enumerated() {
            guard let v = value else { continue }
            if let li = lastIndex {
                let lv = result[li]
                let span = Double(i - li)
                for k in (li + 1)..<i {
                    result[k] = lv + (v - lv) * Double(k - li) / span
                }
            } else {
                for k in 0..<i { result[k] = v }
            }
            result[i] = v
            lastIndex = i
        }
        if let li = lastIndex {
            for k in (li + 1)..<values.count { result[k] = result[li] }
        }
        return result
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }
}

// MARK: - 고도

struct ElevationSample: Identifiable {
    let id: Int
    let km: Double
    let meters: Double
}

struct ElevationSummary {
    enum Source { case barometer, gps }

    let source: Source
    let ascent: Double        // 오르막 누적(m)
    let descent: Double       // 내리막 누적(m)
    let maxAltitude: Double
    let minAltitude: Double
    let maxGrade: Double      // 가장 가파른 200m 구간의 경사(%)
    let samples: [ElevationSample]
}

enum ElevationAnalyzer {
    static func analyze(_ points: [TrackPoint]) -> ElevationSummary? {
        let n = points.count
        guard n >= 10 else { return nil }

        var dist = [Double](repeating: 0, count: n)
        for i in 1..<n {
            dist[i] = dist[i - 1] + points[i - 1].location.distance(from: points[i].location)
        }

        let baroCount = points.reduce(0) { $0 + ($1.baro == nil ? 0 : 1) }
        let gpsCount = points.reduce(0) { $0 + ($1.alt == nil ? 0 : 1) }
        let source: ElevationSummary.Source
        let raw: [Double?]
        if Double(baroCount) >= Double(n) * 0.95 {
            // 기압계는 높이 '변화'가 정확함. 해발 높이는 GPS 고도의 중앙값으로 맞춤
            let offsets = points.compactMap { p -> Double? in
                guard let a = p.alt, let b = p.baro else { return nil }
                return a - b
            }
            let base = Series.median(offsets) ?? 0
            raw = points.map { p in p.baro.map { base + $0 } }
            source = .barometer
        } else if Double(gpsCount) >= Double(n) * 0.5 {
            raw = points.map(\.alt)
            source = .gps
        } else {
            return nil
        }

        let smoothed = Series.movingAverage(Series.fillGaps(raw), radius: source == .barometer ? 2 : 6)

        // 작은 흔들림은 빼고 실제 오르내림만 누적
        let threshold = source == .barometer ? 1.5 : 4.0
        var ascent = 0.0
        var descent = 0.0
        var reference = smoothed[0]
        for v in smoothed.dropFirst() {
            if v - reference >= threshold {
                ascent += v - reference
                reference = v
            } else if reference - v >= threshold {
                descent += reference - v
                reference = v
            }
        }

        // 200m 구간 단위로 가장 가파른 경사
        var maxGrade = 0.0
        var j = 0
        for i in 0..<n {
            if j < i { j = i }
            while j < n - 1 && dist[j] - dist[i] < 200 { j += 1 }
            let run = dist[j] - dist[i]
            if run < 150 { break }
            maxGrade = max(maxGrade, abs(smoothed[j] - smoothed[i]) / run * 100)
        }

        // 그래프용 표본 (최대 약 300개)
        let stepSize = max(1, n / 300)
        var samples: [ElevationSample] = stride(from: 0, to: n, by: stepSize).map { i in
            ElevationSample(id: i, km: dist[i] / 1000, meters: smoothed[i])
        }
        if let last = samples.last, last.id != n - 1 {
            samples.append(ElevationSample(id: n - 1, km: dist[n - 1] / 1000, meters: smoothed[n - 1]))
        }

        return ElevationSummary(
            source: source,
            ascent: ascent,
            descent: descent,
            maxAltitude: smoothed.max() ?? 0,
            minAltitude: smoothed.min() ?? 0,
            maxGrade: maxGrade,
            samples: samples
        )
    }
}

// MARK: - 커브

struct Curve: Identifiable {
    enum Kind { case gentle, sharp, hairpin }

    let id: Int
    let angle: Double           // 꺾인 각도(도). +는 오른쪽, -는 왼쪽
    let radius: Double          // 대략적인 회전 반경(m)
    let coordinate: CLLocationCoordinate2D
    let minSpeedKmh: Double     // 커브를 지날 때 가장 느린 속도

    var kind: Kind {
        let a = abs(angle)
        if a >= 135 { return .hairpin }
        if a >= 90 { return .sharp }
        return .gentle
    }
}

struct CurveSummary {
    let curves: [Curve]
    let distanceKm: Double

    var count: Int { curves.count }
    var sharpCount: Int { curves.filter { $0.kind == .sharp }.count }
    var hairpinCount: Int { curves.filter { $0.kind == .hairpin }.count }
    var perKm: Double { distanceKm >= 0.5 ? Double(count) / distanceKm : 0 }
    var sharpestAngle: Double? { curves.map { abs($0.angle) }.max() }

    /// 급커브·헤어핀을 지날 때의 평균 속도
    var tightCornerSpeed: Double? {
        let tight = curves.filter { $0.kind != .gentle }
        guard !tight.isEmpty else { return nil }
        return tight.reduce(0) { $0 + $1.minSpeedKmh } / Double(tight.count)
    }
}

enum CurveAnalyzer {
    static let step: Double = 10            // 경로를 10m 간격으로 다시 나눠 계산
    static let minTurnRate: Double = 2.5    // 10m에 2.5도 이상 꺾이면 커브 구간 (반경 약 230m 이하)
    static let minAngle: Double = 30        // 한 방향으로 30도 이상 꺾여야 커브 1개

    private struct Sample {
        var x: Double
        var y: Double
        var lat: Double
        var lon: Double
        var kmh: Double
    }

    static func analyze(_ points: [TrackPoint]) -> CurveSummary {
        var curves: [Curve] = []
        var totalDistance = 0.0
        var chunk: [TrackPoint] = []

        // GPS가 끊긴 곳에서 나눠 각각 계산 (끊긴 직선을 커브로 오해하지 않도록)
        for (i, p) in points.enumerated() {
            if i > 0 {
                let prev = points[i - 1]
                totalDistance += prev.location.distance(from: p.location)
                if TrackPoint.isGap(prev, p) {
                    curves += detect(resample(chunk), firstID: curves.count)
                    chunk.removeAll()
                }
            }
            chunk.append(p)
        }
        curves += detect(resample(chunk), firstID: curves.count)
        return CurveSummary(curves: curves, distanceKm: totalDistance / 1000)
    }

    /// 위치 점들을 일정한 거리(10m) 간격의 점으로 바꿈
    private static func resample(_ pts: [TrackPoint]) -> [Sample] {
        guard pts.count >= 2 else { return [] }
        let lat0 = pts[0].lat
        let lon0 = pts[0].lon
        let mx = cos(lat0 * .pi / 180) * 111_320.0
        let my = 110_540.0

        // 미터 좌표로 바꾸고, GPS 흔들림을 줄이려 앞뒤 1점과 평균
        let xs = Series.movingAverage(pts.map { ($0.lon - lon0) * mx }, radius: 1)
        let ys = Series.movingAverage(pts.map { ($0.lat - lat0) * my }, radius: 1)

        func sample(_ x: Double, _ y: Double, _ kmh: Double) -> Sample {
            Sample(x: x, y: y, lat: lat0 + y / my, lon: lon0 + x / mx, kmh: kmh)
        }

        var out: [Sample] = [sample(xs[0], ys[0], pts[0].speedKmh)]
        var px = xs[0]
        var py = ys[0]
        var carry = 0.0
        for i in 1..<pts.count {
            let qx = xs[i]
            let qy = ys[i]
            let segment = hypot(qx - px, qy - py)
            if segment <= 0 { continue }
            let v0 = pts[i - 1].speedKmh
            let v1 = pts[i].speedKmh
            var along = step - carry
            while along <= segment {
                let f = along / segment
                out.append(sample(px + (qx - px) * f, py + (qy - py) * f, v0 + (v1 - v0) * f))
                along += step
            }
            carry = segment - (along - step)
            px = qx
            py = qy
        }
        return out
    }

    private static func detect(_ s: [Sample], firstID: Int) -> [Curve] {
        guard s.count >= 4 else { return [] }

        // 10m마다 진행 방향(북쪽 기준 시계방향 각도)
        var heading: [Double] = []
        for k in 0..<(s.count - 1) {
            heading.append(atan2(s[k + 1].x - s[k].x, s[k + 1].y - s[k].y) * 180 / .pi)
        }
        // 10m마다 방향이 얼마나 바뀌었는지
        var turns: [Double] = []
        for k in 0..<(heading.count - 1) {
            var d = heading[k + 1] - heading[k]
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            turns.append(d)
        }
        let smooth = Series.movingAverage(turns, radius: 2)

        var result: [Curve] = []
        var start = -1
        var lastActive = -1
        var sign = 0.0
        var sum = 0.0
        var quiet = 0

        func close() {
            if start >= 0, lastActive >= start, abs(sum) >= minAngle {
                let end = lastActive
                let arc = Double(end - start + 1) * step
                let radius = arc / (abs(sum) * .pi / 180)
                let apexTurn = (start...end).max { abs(smooth[$0]) < abs(smooth[$1]) } ?? start
                let apex = s[min(apexTurn + 1, s.count - 1)]
                let minKmh = s[start...min(end + 2, s.count - 1)].map(\.kmh).min() ?? apex.kmh
                result.append(Curve(
                    id: firstID + result.count,
                    angle: sum,
                    radius: radius,
                    coordinate: CLLocationCoordinate2D(latitude: apex.lat, longitude: apex.lon),
                    minSpeedKmh: minKmh
                ))
            }
            start = -1
            sum = 0
            sign = 0
            quiet = 0
        }

        for k in smooth.indices {
            let t = smooth[k]
            if abs(t) >= minTurnRate {
                let sg: Double = t > 0 ? 1 : -1
                if start >= 0 && sg != sign { close() }     // 반대 방향으로 꺾이면 새 커브 (S자)
                if start < 0 {
                    start = k
                    sign = sg
                }
                sum += t
                quiet = 0
                lastActive = k
            } else if start >= 0 {
                quiet += 1
                if quiet > 2 { close() }                     // 30m 넘게 곧으면 커브 끝
            }
        }
        close()
        return result
    }
}
