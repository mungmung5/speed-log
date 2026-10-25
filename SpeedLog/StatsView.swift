import SwiftUI
import Charts

/// 한 달(또는 전체) 합계
struct MonthStat: Identifiable {
    let month: Date
    var count = 0
    var distance: Double = 0
    var duration: TimeInterval = 0
    var movingTime: TimeInterval = 0
    var maxSpeed: Double = 0
    var curves = 0
    var hairpins = 0
    var ascent: Double = 0

    var id: Date { month }
    var averageSpeed: Double { duration > 0 ? distance / duration : 0 }

    mutating func add(_ trip: Trip) {
        count += 1
        distance += trip.distance
        duration += trip.duration
        movingTime += trip.movingTime
        maxSpeed = max(maxSpeed, trip.maxSpeed)
        curves += trip.curveCount ?? 0
        hairpins += trip.hairpinCount ?? 0
        ascent += trip.ascent ?? 0
    }

    static func monthly(_ trips: [Trip]) -> [MonthStat] {
        let calendar = Calendar.current
        var byMonth: [Date: MonthStat] = [:]
        for trip in trips {
            let month = calendar.dateInterval(of: .month, for: trip.start)?.start ?? trip.start
            var stat = byMonth[month] ?? MonthStat(month: month)
            stat.add(trip)
            byMonth[month] = stat
        }
        return byMonth.values.sorted { $0.month > $1.month }
    }

    static func total(_ trips: [Trip]) -> MonthStat {
        var stat = MonthStat(month: .distantPast)
        for trip in trips { stat.add(trip) }
        return stat
    }

    /// 최근 12개월 (기록 없는 달도 0으로 포함)
    static func lastTwelveMonths(_ monthly: [MonthStat]) -> [MonthStat] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: monthly.map { ($0.month, $0) })
        return (0..<12).reversed().compactMap { offset in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return lookup[m] ?? MonthStat(month: m)
        }
    }
}

/// 통계 탭
struct StatsView: View {
    @EnvironmentObject private var store: TripStore

    var body: some View {
        NavigationStack {
            Group {
                if store.trips.isEmpty {
                    ContentUnavailableView(
                        "아직 통계가 없어요",
                        systemImage: "chart.bar",
                        description: Text("주행을 기록하면 월별 통계가 나와요.")
                    )
                } else {
                    content(monthly: MonthStat.monthly(store.trips))
                }
            }
            .navigationTitle("통계")
        }
    }

    private func content(monthly: [MonthStat]) -> some View {
        let calendar = Calendar.current
        let thisMonthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let thisMonth = monthly.first { $0.month == thisMonthStart } ?? MonthStat(month: thisMonthStart)
        let total = MonthStat.total(store.trips)
        let chartData = MonthStat.lastTwelveMonths(monthly)

        return List {
            Section("이번 달") {
                summaryGrid(thisMonth)
            }
            Section("최근 12개월 주행 거리") {
                Chart(chartData) { m in
                    BarMark(
                        x: .value("월", m.month, unit: .month),
                        y: .value("거리", m.distance / 1000)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
                .chartYAxisLabel("km")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 8)
            }
            Section("월별") {
                ForEach(monthly) { m in
                    MonthRow(stat: m)
                }
            }
            Section("전체") {
                summaryGrid(total)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func summaryGrid(_ s: MonthStat) -> some View {
        let tile = Color(.secondarySystemGroupedBackground)
        return         Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "운행", value: "\(s.count)회", background: tile)
                StatTile(title: "거리", value: Fmt.km(s.distance), background: tile)
            }
            GridRow {
                StatTile(title: "운행 시간", value: Fmt.duration(s.duration), background: tile)
                StatTile(title: "평균 속도", value: Fmt.kmh(s.averageSpeed), background: tile)
            }
            GridRow {
                StatTile(title: "최고 속도", value: Fmt.kmh(s.maxSpeed), background: tile)
                StatTile(title: "1회 평균 거리", value: Fmt.km(s.count > 0 ? s.distance / Double(s.count) : 0), background: tile)
            }
            GridRow {
                StatTile(title: "커브 (헤어핀)", value: "\(s.curves)개 (\(s.hairpins))", background: tile)
                StatTile(title: "누적 오르막", value: Fmt.meters(s.ascent), background: tile)
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .listRowBackground(Color.clear)
    }
}

struct MonthRow: View {
    let stat: MonthStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.month.string(from: stat.month))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.km(stat.distance))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            HStack(spacing: 12) {
                Label("\(stat.count)회", systemImage: "car")
                Label(Fmt.duration(stat.duration), systemImage: "clock")
                Label("평균 \(Fmt.speedNumber(stat.averageSpeed))", systemImage: "speedometer")
                Label("최고 \(Fmt.speedNumber(stat.maxSpeed))", systemImage: "bolt.fill")
                Label("커브 \(stat.curves)", systemImage: "scribble.variable")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
