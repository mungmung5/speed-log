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
    @State private var elevation: ElevationSummary?
    @State private var curveSummary: CurveSummary?
    @State private var loaded = false
    @State private var shareItem: ShareItem?
    @State private var confirmDelete = false

    /// 이름이 나중에 채워질 수 있어 저장소의 최신 값을 사용
    private var current: Trip { store.trips.first { $0.id == trip.id } ?? trip }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    mapSection
                    statsSection
                        .id("stats")
                    if let c = curveSummary, points.count >= 2 {
                        curveSection(c)
                            .id("curves")
                    }
                    if let e = elevation {
                        elevationSection(e)
                            .id("elevation")
                    }
                    if samples.count > 2 {
                        chartSection
                            .id("speed")
                    }
                }
                .padding()
            }
            .onChange(of: loaded) { _, isLoaded in
                // 화면 캡처용: 지정한 구간으로 스크롤
                guard isLoaded, let target = Demo.value("-detailSection") else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo(target, anchor: .top)
                }
            }
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
            let curves = CurveAnalyzer.analyze(pts)
            let elev = ElevationAnalyzer.analyze(pts)
            points = pts
            samples = SpeedSample.make(from: pts)
            curveSummary = curves
            elevation = elev
            loaded = true
            // 이전 버전에서 기록한 운행이면 분석 결과를 저장
            if current.curveCount == nil, pts.count >= 2 {
                var updated = current
                updated.apply(elevation: elev, curves: curves)
                store.update(updated)
            }
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
                RouteMapView(points: points, maxSpeedAt: current.maxSpeedAt, curves: curveSummary?.curves ?? [])
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

    private func sectionTitle(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .padding(.top, 8)
    }

    private func curveSection(_ c: CurveSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("커브 분석", "scribble.variable")
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: "커브", value: "\(c.count)개")
                    StatTile(title: "1km당 커브", value: String(format: "%.1f개", c.perKm))
                }
                GridRow {
                    StatTile(title: "급커브 (90° 이상)", value: "\(c.sharpCount)개")
                    StatTile(title: "헤어핀 (135° 이상)", value: "\(c.hairpinCount)개")
                }
                GridRow {
                    StatTile(
                        title: "급커브 평균 통과 속도",
                        value: c.tightCornerSpeed.map { "\(Int($0.rounded())) km/h" } ?? "–"
                    )
                    StatTile(
                        title: "가장 많이 꺾인 커브",
                        value: c.sharpestAngle.map { "\(Int($0.rounded()))°" } ?? "–"
                    )
                }
            }
            Text("한 방향으로 30° 이상 꺾이는 곳을 커브 1개로 셉니다. 지도의 '커브' 버튼을 누르면 급커브(주황)와 헤어핀(빨강) 위치가 표시돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func elevationSection(_ e: ElevationSummary) -> some View {
        let pad = max(10, (e.maxAltitude - e.minAltitude) * 0.1)
        let low = e.minAltitude - pad
        let high = e.maxAltitude + pad
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("고도", "mountain.2")
            Chart(e.samples) { s in
                AreaMark(
                    x: .value("거리", s.km),
                    yStart: .value("기준", low),
                    yEnd: .value("고도", s.meters)
                )
                .foregroundStyle(Color.brown.opacity(0.2))
                LineMark(
                    x: .value("거리", s.km),
                    y: .value("고도", s.meters)
                )
                .foregroundStyle(Color.brown)
            }
            .chartYScale(domain: low...high)
            .chartXAxisLabel("km")
            .chartYAxisLabel("m")
            .frame(height: 160)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: "오르막 누적", value: Fmt.meters(e.ascent))
                    StatTile(title: "내리막 누적", value: Fmt.meters(e.descent))
                }
                GridRow {
                    StatTile(title: "최고 고도", value: Fmt.meters(e.maxAltitude))
                    StatTile(title: "최저 고도", value: Fmt.meters(e.minAltitude))
                }
                GridRow {
                    StatTile(title: "가장 가파른 곳", value: String(format: "%.0f%%", e.maxGrade))
                    StatTile(title: "고도 측정", value: e.source == .barometer ? "기압계" : "GPS")
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("속도 변화", "speedometer")
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
        // 그래프가 들쭉날쭉하지 않게 앞뒤 2칸 평균
        let smoothed = Series.movingAverage(result.map(\.kmh), radius: 2)
        return result.enumerated().map { i, s in
            SpeedSample(id: s.id, time: s.time, kmh: smoothed[i])
        }
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

            if TrackPoint.isGap(prev, p) {
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
    private let tightCurves: [Curve]
    @State private var satellite = Demo.has("-satellite")
    @State private var showCurves = Demo.has("-showCurves")

    init(points: [TrackPoint], maxSpeedAt: Date?, curves: [Curve]) {
        self.points = points
        self.maxSpeedAt = maxSpeedAt
        self.segments = RouteSegment.build(from: points)
        self.tightCurves = curves.filter { $0.kind != .gentle }
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
            if showCurves {
                ForEach(tightCurves) { curve in
                    Annotation("", coordinate: curve.coordinate) {
                        Circle()
                            .fill(curve.kind == .hairpin ? Color.red : Color.orange)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
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
            HStack(spacing: 6) {
                mapButton(
                    showCurves ? "커브 숨기기" : "커브",
                    icon: "scribble.variable",
                    active: showCurves
                ) { showCurves.toggle() }
                mapButton(
                    satellite ? "지도" : "위성",
                    icon: satellite ? "map" : "globe.asia.australia",
                    active: false
                ) { satellite.toggle() }
            }
            .padding(8)
        }
    }

    private func mapButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(active ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Material.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
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
