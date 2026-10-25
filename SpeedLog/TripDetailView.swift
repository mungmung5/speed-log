import SwiftUI
import MapKit
import Charts

/// 운행 하나의 상세: 지도, 수치, 속도 그래프
struct TripDetailView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var points: [TrackPoint] = []
    @State private var samples: [SpeedSample] = []
    @State private var loaded = false
    @State private var shareItem: ShareItem?
    @State private var confirmDelete = false

    /// 이름이 나중에 채워질 수 있어 저장소의 최신 값을 사용
    private var current: Trip { store.trips.first { $0.id == trip.id } ?? trip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                mapSection
                statsSection
                if samples.count > 2 {
                    chartSection
                }
            }
            .padding()
        }
        .navigationTitle(Fmt.dateTime.string(from: trip.start))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let url = try? store.exportGPX(current) { shareItem = ShareItem(url: url) }
                    } label: {
                        Label("GPX 파일로 내보내기", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("이 주행 기록을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                store.delete(current)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .task {
            let pts = store.points(for: trip)
            points = pts
            samples = SpeedSample.make(from: pts)
            loaded = true
            await store.resolveNamesIfNeeded(trip.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(current.routeTitle)
                .font(.title3.weight(.bold))
            Text(Fmt.date.string(from: current.start))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if points.count < 2 {
            Text("경로 정보가 없어요.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                RouteMapView(points: points, maxSpeedAt: current.maxSpeedAt)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                SpeedLegend()
            }
        }
    }

    private var statsSection: some View {
        let t = current
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "출발", value: Fmt.time.string(from: t.start))
                StatTile(title: "도착", value: Fmt.time.string(from: t.end))
            }
            GridRow {
                StatTile(title: "운행 시간", value: Fmt.duration(t.duration))
                StatTile(title: "거리", value: Fmt.km(t.distance))
            }
            GridRow {
                StatTile(title: "평균 속도", value: Fmt.kmh(t.averageSpeed))
                StatTile(title: "최고 속도", value: Fmt.kmh(t.maxSpeed))
            }
            GridRow {
                StatTile(title: "주행 시간 (정차 제외)", value: Fmt.duration(t.movingTime))
                StatTile(title: "주행 중 평균", value: Fmt.kmh(t.movingAverageSpeed))
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("속도 변화")
                .font(.headline)
            Chart(samples) { s in
                AreaMark(
                    x: .value("시간", s.time),
                    y: .value("속도", s.kmh)
                )
                .foregroundStyle(Color.blue.opacity(0.15))
                LineMark(
                    x: .value("시간", s.time),
                    y: .value("속도", s.kmh)
                )
                .foregroundStyle(Color.blue)
            }
            .chartYAxisLabel("km/h")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 180)
        }
    }
}

/// 그래프용 속도 표본 (점이 많으면 구간 평균으로 줄임)
struct SpeedSample: Identifiable {
    let id: Int
    let time: Date
    let kmh: Double

    static func make(from points: [TrackPoint], maxCount: Int = 300) -> [SpeedSample] {
        guard !points.isEmpty else { return [] }
        let bucket = max(1, Int((Double(points.count) / Double(maxCount)).rounded(.up)))
        var result: [SpeedSample] = []
        var i = 0
        while i < points.count {
            let slice = points[i..<min(i + bucket, points.count)]
            let avg = slice.reduce(0) { $0 + $1.speedKmh } / Double(slice.count)
            result.append(SpeedSample(id: result.count, time: slice[slice.startIndex].t, kmh: avg))
            i += bucket
        }
        return result
    }
}

/// 속도에 따라 색을 나눈 경로 조각
struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    let isGap: Bool

    static let colors: [Color] = [.green, .yellow, .orange, .red]

    static func bucket(_ kmh: Double) -> Int {
        if kmh < 40 { return 0 }
        if kmh < 80 { return 1 }
        if kmh < 110 { return 2 }
        return 3
    }

    /// 각 구간 색의 시작 속도(km/h)
    private static let lowerBounds: [Double] = [0, 40, 80, 110]

    /// 두 점 사이가 GPS 끊김(터널, 깊은 계곡 등)인지
    static func isGap(_ a: TrackPoint, _ b: TrackPoint) -> Bool {
        let seconds = b.t.timeIntervalSince(a.t)
        return seconds > 10 && a.location.distance(from: b.location) > 150
    }

    /// 기록한 점을 하나도 빼지 않고 그대로 이어 그림 (구불구불한 길도 그대로 보이게)
    static func build(from points: [TrackPoint]) -> [RouteSegment] {
        guard points.count > 1 else { return [] }

        // 색이 너무 자주 바뀌지 않도록 앞뒤 5초 평균 속도로 판단
        let speeds = points.map(\.speedKmh)
        let smoothed: [Double] = speeds.indices.map { i in
            let lo = max(0, i - 5)
            let hi = min(speeds.count - 1, i + 5)
            let window = speeds[lo...hi]
            return window.reduce(0, +) / Double(window.count)
        }

        var result: [RouteSegment] = []
        var current: [CLLocationCoordinate2D] = [points[0].coordinate]
        var currentBucket = bucket(smoothed[0])

        func flush() {
            if current.count > 1 {
                result.append(RouteSegment(id: result.count, coordinates: current, color: colors[currentBucket], isGap: false))
            }
        }

        for i in 1..<points.count {
            let prev = points[i - 1]
            let p = points[i]

            if isGap(prev, p) {
                // 끊긴 구간은 회색 점선으로 따로 그림
                flush()
                result.append(RouteSegment(id: result.count, coordinates: [prev.coordinate, p.coordinate], color: .gray, isGap: true))
                current = [p.coordinate]
                currentBucket = bucket(smoothed[i])
                continue
            }

            current.append(p.coordinate)
            let v = smoothed[i]
            let candidate = bucket(v)
            // 경계 근처에서 색이 깜빡이지 않도록 3 km/h 여유를 둠
            let crossedUp = candidate > currentBucket && v >= lowerBounds[candidate] + 3
            let crossedDown = candidate < currentBucket && v <= lowerBounds[currentBucket] - 3
            if crossedUp || crossedDown {
                flush()
                current = [p.coordinate]
                currentBucket = candidate
            }
        }
        flush()
        return result
    }
}

struct RouteMapView: View {
    let points: [TrackPoint]
    let maxSpeedAt: Date?
    private let segments: [RouteSegment]
    @State private var satellite = false

    init(points: [TrackPoint], maxSpeedAt: Date?) {
        self.points = points
        self.maxSpeedAt = maxSpeedAt
        self.segments = RouteSegment.build(from: points)
    }

    private var maxPoint: TrackPoint? {
        guard let at = maxSpeedAt else { return nil }
        return points.min { abs($0.t.timeIntervalSince(at)) < abs($1.t.timeIntervalSince(at)) }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        segment.color,
                        style: segment.isGap
                            ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6])
                            : StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
            if let first = points.first {
                Marker("출발", systemImage: "flag.fill", coordinate: first.coordinate)
                    .tint(.green)
            }
            if let last = points.last {
                Marker("도착", systemImage: "flag.checkered", coordinate: last.coordinate)
                    .tint(.red)
            }
            if let top = maxPoint {
                Marker("최고 \(Fmt.speedNumber(top.speed)) km/h", systemImage: "bolt.fill", coordinate: top.coordinate)
                    .tint(.purple)
            }
        }
        .mapStyle(
            satellite
                ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                : .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                satellite.toggle()
            } label: {
                Label(satellite ? "지도" : "위성", systemImage: satellite ? "map" : "globe.asia.australia")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}

struct SpeedLegend: View {
    private let items: [(String, Color)] = [
        ("~40", .green), ("40~80", .yellow), ("80~110", .orange), ("110~", .red)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Capsule()
                        .fill(items[i].1)
                        .frame(width: 16, height: 5)
                    Text(items[i].0)
                }
            }
            Text("km/h")
            Spacer()
            HStack(spacing: 4) {
                Capsule()
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 16, height: 1)
                Text("GPS 끊김")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
