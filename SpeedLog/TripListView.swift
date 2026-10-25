import SwiftUI

/// 월별로 묶은 운행 목록
struct MonthGroup: Identifiable {
    let month: Date
    let trips: [Trip]
    var id: Date { month }
    var distance: Double { trips.reduce(0) { $0 + $1.distance } }

    static func make(_ trips: [Trip]) -> [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: trips) { trip in
            calendar.dateInterval(of: .month, for: trip.start)?.start ?? trip.start
        }
        return grouped.keys.sorted(by: >).map { key in
            MonthGroup(month: key, trips: (grouped[key] ?? []).sorted { $0.start > $1.start })
        }
    }
}

/// 기록 탭
struct TripListView: View {
    @EnvironmentObject private var store: TripStore
    @State private var pendingDelete: Trip?

    var body: some View {
        NavigationStack {
            Group {
                if store.trips.isEmpty {
                    ContentUnavailableView(
                        "아직 주행 기록이 없어요",
                        systemImage: "car",
                        description: Text("주행 탭에서 기록을 시작하세요.")
                    )
                } else {
                    tripList
                }
            }
            .navigationTitle("운행 기록")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .alert(
                "이 주행 기록을 삭제할까요?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { trip in
                Button("삭제", role: .destructive) { store.delete(trip) }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("삭제하면 되돌릴 수 없어요.")
            }
            .task {
                store.analyzeMissing()
                await store.resolveMissingNames()
            }
        }
    }

    private var tripList: some View {
        List {
            ForEach(MonthGroup.make(store.trips)) { group in
                Section {
                    ForEach(group.trips) { trip in
                        NavigationLink(value: trip) {
                            TripRow(trip: trip)
                        }
                        .swipeActions {
                            Button("삭제", role: .destructive) { pendingDelete = trip }
                        }
                    }
                } header: {
                    HStack {
                        Text(Fmt.month.string(from: group.month))
                        Spacer()
                        Text("\(group.trips.count)회 · \(Fmt.km(group.distance))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.dateTime.string(from: trip.start))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.km(trip.distance))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Text(trip.routeTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 10) {
                Label(Fmt.duration(trip.duration), systemImage: "clock")
                Label("평균 \(Fmt.speedNumber(trip.averageSpeed))", systemImage: "speedometer")
                Label("최고 \(Fmt.speedNumber(trip.maxSpeed))", systemImage: "bolt.fill")
                if let curves = trip.curveCount {
                    Label("커브 \(curves)", systemImage: "scribble.variable")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
