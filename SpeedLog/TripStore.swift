import Foundation
import CoreLocation

/// 운행 기록 저장소 (아이폰 안 Documents/SpeedLog 폴더)
@MainActor
final class TripStore: ObservableObject {
    static let shared = TripStore()

    /// 최신 운행이 앞에 오도록 정렬
    @Published private(set) var trips: [Trip] = []

    private let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("trips.json") }
    private var routesFolder: URL { folder.appendingPathComponent("routes", isDirectory: true) }
    private var activeURL: URL { folder.appendingPathComponent("current.json") }

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
        folder = docs.appendingPathComponent(Demo.isOn ? "SpeedLogDemo" : "SpeedLog", isDirectory: true)
        if Demo.isOn { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(
            at: folder.appendingPathComponent("routes", isDirectory: true),
            withIntermediateDirectories: true
        )
        load()
        if Demo.isOn {
            for (trip, points) in Demo.makeTrips() { add(trip, points: points) }
        }
    }

    // MARK: - 운행 목록

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? Self.decoder.decode([Trip].self, from: data) else {
            trips = []
            return
        }
        trips = list.sorted { $0.start > $1.start }
    }

    private func saveIndex() {
        guard let data = try? Self.encoder.encode(trips) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func routeURL(_ id: UUID) -> URL {
        routesFolder.appendingPathComponent("\(id.uuidString).json")
    }

    func add(_ trip: Trip, points: [TrackPoint]) {
        if let data = try? Self.encoder.encode(points) {
            try? data.write(to: routeURL(trip.id), options: .atomic)
        }
        trips.removeAll { $0.id == trip.id }
        trips.append(trip)
        trips.sort { $0.start > $1.start }
        saveIndex()
    }

    func update(_ trip: Trip) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        saveIndex()
    }

    /// 커브·고도 분석이 없는 운행(이전 버전에서 기록한 것)을 분석해 채움
    func analyzeMissing() {
        var changed = false
        for idx in trips.indices where trips[idx].curveCount == nil {
            let pts = points(for: trips[idx])
            guard pts.count >= 2 else { continue }
            trips[idx].analyze(pts)
            changed = true
        }
        if changed { saveIndex() }
    }

    /// 이 폰의 주행 기록을 모두 지움 (탈퇴할 때 선택)
    func deleteAll() {
        try? FileManager.default.removeItem(at: routesFolder)
        try? FileManager.default.createDirectory(at: routesFolder, withIntermediateDirectories: true)
        trips = []
        saveIndex()
    }

    func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: routeURL(trip.id))
        trips.removeAll { $0.id == trip.id }
        saveIndex()
    }

    func points(for trip: Trip) -> [TrackPoint] {
        guard let data = try? Data(contentsOf: routeURL(trip.id)) else { return [] }
        return (try? Self.decoder.decode([TrackPoint].self, from: data)) ?? []
    }

    // MARK: - 출발지·도착지 이름

    func resolveNamesIfNeeded(_ id: UUID) async {
        guard let trip = trips.first(where: { $0.id == id }),
              trip.startName == nil || trip.endName == nil else { return }
        let pts = points(for: trip)
        guard let first = pts.first, let last = pts.last else { return }
        let startName = await Self.placeName(first.location)
        let endName = await Self.placeName(last.location)
        guard let idx = trips.firstIndex(where: { $0.id == id }) else { return }
        if trips[idx].startName == nil { trips[idx].startName = startName }
        if trips[idx].endName == nil { trips[idx].endName = endName }
        saveIndex()
    }

    /// 이름이 비어 있는 최근 운행 몇 개를 채움
    func resolveMissingNames() async {
        let missing = trips.prefix(30).filter { $0.startName == nil || $0.endName == nil }.prefix(10)
        for trip in missing {
            await resolveNamesIfNeeded(trip.id)
        }
    }

    private static func placeName(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(
            location, preferredLocale: Locale(identifier: "ko_KR")
        ), let pm = placemarks.first else { return nil }

        var parts: [String] = []
        if let city = pm.locality ?? pm.administrativeArea { parts.append(city) }
        if let area = pm.subLocality, !parts.contains(area) { parts.append(area) }
        if parts.isEmpty, let name = pm.name { parts.append(name) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - 기록 중인 운행 임시 저장

    func saveActive(_ snapshot: ActiveTripSnapshot) {
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        try? data.write(to: activeURL, options: .atomic)
    }

    func loadActive() -> ActiveTripSnapshot? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? Self.decoder.decode(ActiveTripSnapshot.self, from: data)
    }

    func clearActive() {
        try? FileManager.default.removeItem(at: activeURL)
    }

    // MARK: - 내보내기 / 불러오기

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func exportBackup() throws -> URL {
        let backup = Backup(
            version: 1,
            exportedAt: Date(),
            trips: trips.map { BackupTrip(trip: $0, points: points(for: $0)) }
        )
        let data = try Self.encoder.encode(backup)
        let url = tempURL("SpeedLog-backup-\(Fmt.fileStamp.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 백업 파일을 불러와 없는 운행만 추가. 추가한 개수를 돌려줌
    func importBackup(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let backup = try Self.decoder.decode(Backup.self, from: data)
        var added = 0
        for item in backup.trips where !trips.contains(where: { $0.id == item.trip.id }) {
            if let pointData = try? Self.encoder.encode(item.points) {
                try? pointData.write(to: routeURL(item.trip.id), options: .atomic)
            }
            trips.append(item.trip)
            added += 1
        }
        trips.sort { $0.start > $1.start }
        saveIndex()
        return added
    }

    func exportCSV() throws -> URL {
        func field(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func num(_ v: Double, _ digits: Int = 1) -> String {
            String(format: "%.\(digits)f", v)
        }
        var lines = ["출발,도착,출발지,도착지,운행시간(분),주행시간(분),거리(km),평균속도(km/h),주행평균(km/h),최고속도(km/h),오르막(m),내리막(m),최고고도(m),커브,급커브,헤어핀"]
        func optD(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "" }
        func optI(_ v: Int?) -> String { v.map(String.init) ?? "" }
        for t in trips.sorted(by: { $0.start < $1.start }) {
            lines.append([
                Fmt.csv.string(from: t.start),
                Fmt.csv.string(from: t.end),
                field(t.startName ?? ""),
                field(t.endName ?? ""),
                num(t.duration / 60, 0),
                num(t.movingTime / 60, 0),
                num(t.distance / 1000, 2),
                num(t.averageSpeed * 3.6),
                num(t.movingAverageSpeed * 3.6),
                num(t.maxSpeed * 3.6),
                optD(t.ascent),
                optD(t.descent),
                optD(t.maxAltitude),
                optI(t.curveCount),
                optI(t.sharpCurveCount),
                optI(t.hairpinCount)
            ].joined(separator: ","))
        }
        // 엑셀에서 한글이 깨지지 않도록 BOM 추가
        let text = "\u{FEFF}" + lines.joined(separator: "\n")
        let url = tempURL("SpeedLog-\(Fmt.fileStamp.string(from: Date())).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportGPX(_ trip: Trip) throws -> URL {
        let iso = ISO8601DateFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Speed Log" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(Fmt.dateTime.string(from: trip.start))</name><trkseg>

        """
        for p in points(for: trip) {
            xml += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><time>\(iso.string(from: p.t))</time></trkpt>\n"
        }
        xml += "</trkseg></trk></gpx>\n"
        let url = tempURL("SpeedLog-\(Fmt.fileStamp.string(from: trip.start)).gpx")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
