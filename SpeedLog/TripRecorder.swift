import Foundation
import CoreLocation
import CoreMotion

/// GPS로 운행을 기록하고, 자동 시작·자동 종료를 처리
@MainActor
final class TripRecorder: NSObject, ObservableObject {
    static let shared = TripRecorder()

    // MARK: - 화면 표시용 상태

    @Published private(set) var isRecording = false
    @Published private(set) var startDate: Date?
    @Published private(set) var currentSpeed: Double = 0        // m/s
    @Published private(set) var distance: Double = 0            // m
    @Published private(set) var maxSpeed: Double = 0            // m/s
    @Published private(set) var movingTime: TimeInterval = 0
    @Published private(set) var gpsAccuracy: Double?
    @Published private(set) var altitude: Double?               // 현재 해발 고도(m)
    @Published private(set) var liveCurveCount = 0              // 지금까지 지난 커브 수
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var preciseLocation = true
    @Published private(set) var message: String?

    // MARK: - 설정

    /// 차량 이동을 감지하면 자동으로 기록 시작
    @Published var autoDetect: Bool {
        didSet {
            UserDefaults.standard.set(autoDetect, forKey: Keys.autoDetect)
            if autoDetect && manager.authorizationStatus != .authorizedAlways {
                manager.requestAlwaysAuthorization()
            }
            applyMonitoring()
        }
    }

    /// 이 시간(분) 이상 멈춰 있으면 자동 종료. 0이면 끔
    @Published var autoStopMinutes: Int {
        didSet { UserDefaults.standard.set(autoStopMinutes, forKey: Keys.autoStop) }
    }

    private enum Keys {
        static let autoDetect = "autoDetect"
        static let autoStop = "autoStopMinutes"
    }

    // MARK: - 내부 상태

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    private var altimeterRunning = false
    private var baroRelative: Double?        // 기압계: 측정 시작 후 높이 변화(m)
    private var baroUpdatedAt: Date?
    private var baroOffset: Double = 0       // 앱이 다시 켜졌을 때 이어 붙이기 위한 보정값
    private let store: TripStore
    private var accumulator = TripAccumulator()
    private var points: [TrackPoint] = []
    private var tripID = UUID()
    private var autoStarted = false
    private var backgroundSession: CLBackgroundActivitySession?
    private var timer: Timer?
    private var lastSnapshot = Date.distantPast
    private var pendingStart = false
    private var activityRunning = false
    private var monitoringSignificant = false
    private var suppressAutoStartUntil: Date?
    private var messageTask: Task<Void, Never>?

    private override init() {
        let defaults = UserDefaults.standard
        _autoDetect = Published(initialValue: defaults.bool(forKey: Keys.autoDetect))
        _autoStopMinutes = Published(initialValue: defaults.object(forKey: Keys.autoStop) as? Int ?? 5)
        _authorization = Published(initialValue: .notDetermined)
        store = TripStore.shared
        super.init()

        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        preciseLocation = manager.accuracyAuthorization == .fullAccuracy

        recoverActiveTrip()
        applyMonitoring()
    }

    var authorizationText: String {
        switch authorization {
        case .authorizedAlways: return "항상 허용"
        case .authorizedWhenInUse: return "앱 사용 중에만"
        case .denied: return "허용 안 함"
        case .restricted: return "제한됨"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }

    // MARK: - 시작 / 종료

    func start(auto: Bool = false) {
        guard !isRecording else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStart = true
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            show("위치 권한이 꺼져 있어요. 설정 탭에서 권한을 허용해 주세요.")
            return
        default:
            break
        }

        tripID = UUID()
        points = []
        accumulator = TripAccumulator()
        autoStarted = auto
        startDate = Date()
        distance = 0
        maxSpeed = 0
        movingTime = 0
        currentSpeed = 0
        isRecording = true
        beginUpdates()
        saveSnapshot(force: true)
        if auto { show("주행을 감지해 기록을 시작했어요.") }
    }

    /// 기록을 끝내고 저장. trimTo가 있으면 그 시각까지만 저장(정차 구간 제거)
    func stop(trimTo trimDate: Date? = nil, manual: Bool = true) {
        guard isRecording, let start = startDate else { return }
        isRecording = false
        manager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
        timer?.invalidate()
        timer = nil
        // 직접 끈 경우 계속 차 안에 있어도 곧바로 다시 시작하지 않도록 잠시 자동 시작을 막음
        suppressAutoStartUntil = Date().addingTimeInterval(manual ? 15 * 60 : 60)
        store.clearActive()

        var kept = points
        var end = Date()
        if let trimDate {
            kept = kept.filter { $0.t <= trimDate }
            end = trimDate
        }
        let result = accumulator
        let id = tripID
        let wasAuto = autoStarted
        stopAltimeter()
        resetLive()

        guard result.distance >= 100, kept.count >= 2 else {
            show("이동 거리가 너무 짧아 저장하지 않았어요.")
            return
        }

        var trip = Trip(
            id: id,
            start: start,
            end: max(end, start),
            distance: result.distance,
            maxSpeed: result.maxSpeed,
            movingTime: result.movingTime,
            maxSpeedAt: result.maxSpeedAt,
            autoStarted: wasAuto
        )
        trip.analyze(kept)
        store.add(trip, points: kept)
        show("저장했어요 · \(Fmt.km(trip.distance)) · \(Fmt.duration(trip.duration))")
        Task { await store.resolveNamesIfNeeded(id) }
    }

    // MARK: - 위치 처리

    private func beginUpdates(baroOffset offset: Double = 0) {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        if backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        startAltimeter(offset: offset)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRecording else { return }
        liveCurveCount = CurveAnalyzer.analyze(points).count
        checkAutoStop(now: Date())
    }

    // MARK: - 기압계 (고갯길 오르내림을 GPS보다 정확하게)

    private func startAltimeter(offset: Double) {
        guard !altimeterRunning, CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeterRunning = true
        baroOffset = offset
        baroRelative = nil
        baroUpdatedAt = nil
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let value = data.relativeAltitude.doubleValue
            MainActor.assumeIsolated {
                self.baroRelative = value
                self.baroUpdatedAt = Date()
            }
        }
    }

    private func stopAltimeter() {
        guard altimeterRunning else { return }
        altimeter.stopRelativeAltitudeUpdates()
        altimeterRunning = false
        baroRelative = nil
        baroUpdatedAt = nil
    }

    private var currentBaro: Double? {
        guard let r = baroRelative, let at = baroUpdatedAt, Date().timeIntervalSince(at) < 10 else { return nil }
        return baroOffset + r
    }

    private func handle(_ locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        if isRecording {
            gpsAccuracy = latest.horizontalAccuracy
            currentSpeed = max(latest.speed, 0)
            for loc in locations { record(loc) }
            checkAutoStop(now: latest.timestamp)
            saveSnapshot(force: false)
        } else {
            considerAutoStart(with: latest)
        }
    }

    private func record(_ loc: CLLocation) {
        guard let start = startDate, loc.timestamp >= start.addingTimeInterval(-10) else { return }
        let gpsAltitude: Double? = (loc.verticalAccuracy >= 0 && loc.verticalAccuracy <= 30) ? loc.altitude : nil
        if let gpsAltitude { altitude = gpsAltitude }
        let p = TrackPoint(
            t: loc.timestamp,
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            speed: loc.speed,
            acc: loc.horizontalAccuracy,
            alt: gpsAltitude,
            baro: currentBaro
        )
        if accumulator.add(p, speedAccuracy: loc.speedAccuracy) {
            points.append(p)
        }
        distance = accumulator.distance
        maxSpeed = accumulator.maxSpeed
        movingTime = accumulator.movingTime
    }

    private func checkAutoStop(now: Date) {
        guard isRecording, autoStopMinutes > 0, let start = startDate else { return }
        let reference = accumulator.lastMovingAt ?? start
        if now.timeIntervalSince(reference) >= TimeInterval(autoStopMinutes * 60) {
            stop(trimTo: accumulator.lastMovingAt, manual: false)
        }
    }

    private func resetLive() {
        startDate = nil
        currentSpeed = 0
        distance = 0
        maxSpeed = 0
        movingTime = 0
        gpsAccuracy = nil
        altitude = nil
        liveCurveCount = 0
        points = []
        accumulator = TripAccumulator()
    }

    private func saveSnapshot(force: Bool) {
        guard isRecording, let start = startDate else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshot) >= 30 else { return }
        lastSnapshot = now
        store.saveActive(ActiveTripSnapshot(id: tripID, start: start, autoStarted: autoStarted, points: points))
    }

    /// 기록 도중 앱이 종료됐다면 이어서 기록하거나, 오래됐으면 그 시점까지 저장
    private func recoverActiveTrip() {
        guard let snap = store.loadActive() else { return }
        tripID = snap.id
        startDate = snap.start
        autoStarted = snap.autoStarted
        accumulator = TripAccumulator()
        points = []
        for p in snap.points {
            if accumulator.add(p) { points.append(p) }
        }
        distance = accumulator.distance
        maxSpeed = accumulator.maxSpeed
        movingTime = accumulator.movingTime
        isRecording = true

        let lastSeen = snap.points.last?.t ?? snap.start
        let limit = TimeInterval(max(autoStopMinutes, 5) * 60)
        let status = manager.authorizationStatus
        let allowed = status == .authorizedAlways || status == .authorizedWhenInUse
        if !allowed || Date().timeIntervalSince(lastSeen) > limit {
            stop(trimTo: accumulator.lastMovingAt ?? lastSeen, manual: false)
        } else {
            liveCurveCount = CurveAnalyzer.analyze(points).count
            // 기압계는 새로 0부터 재므로 마지막 값에 이어 붙임
            beginUpdates(baroOffset: snap.points.last(where: { $0.baro != nil })?.baro ?? 0)
        }
    }

    // MARK: - 자동 시작

    private func canAutoStart() -> Bool {
        guard autoDetect, !isRecording, manager.authorizationStatus == .authorizedAlways else { return false }
        if let until = suppressAutoStartUntil, Date() < until { return false }
        return true
    }

    private func startIfAllowed() {
        if canAutoStart() { start(auto: true) }
    }

    /// 위치 변화로 앱이 깨어났을 때: 속도가 빠르거나 최근 차량 이동이 감지되면 시작
    private func considerAutoStart(with location: CLLocation) {
        guard canAutoStart() else { return }
        let fresh = abs(location.timestamp.timeIntervalSinceNow) < 120
        if fresh, location.speed >= 7, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 {
            start(auto: true)
            return
        }
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let now = Date()
        motion.queryActivityStarting(from: now.addingTimeInterval(-180), to: now, to: .main) { [weak self] activities, _ in
            guard let self, let activities else { return }
            MainActor.assumeIsolated {
                let driving = activities.suffix(4).contains { $0.automotive && $0.confidence != .low }
                if driving { self.startIfAllowed() }
            }
        }
    }

    private func applyMonitoring() {
        let always = manager.authorizationStatus == .authorizedAlways
        if autoDetect && always {
            if !monitoringSignificant && CLLocationManager.significantLocationChangeMonitoringAvailable() {
                manager.startMonitoringSignificantLocationChanges()
                monitoringSignificant = true
            }
            startActivityUpdates()
        } else {
            if monitoringSignificant {
                manager.stopMonitoringSignificantLocationChanges()
                monitoringSignificant = false
            }
            stopActivityUpdates()
        }
    }

    private func startActivityUpdates() {
        guard !activityRunning, CMMotionActivityManager.isActivityAvailable() else { return }
        activityRunning = true
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            MainActor.assumeIsolated {
                if activity.automotive && activity.confidence != .low {
                    self.startIfAllowed()
                }
            }
        }
    }

    private func stopActivityUpdates() {
        guard activityRunning else { return }
        motion.stopActivityUpdates()
        activityRunning = false
    }

    private func authorizationChanged() {
        authorization = manager.authorizationStatus
        preciseLocation = manager.accuracyAuthorization == .fullAccuracy
        if pendingStart && authorization != .notDetermined {
            pendingStart = false
            if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
                start()
            }
        }
        applyMonitoring()
    }

    // MARK: - 안내 메시지

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

extension TripRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            self.handle(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            self.authorizationChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 일시적인 위치 오류는 무시하고 다음 위치를 기다림
    }
}
