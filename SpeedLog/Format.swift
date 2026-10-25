import Foundation

/// 화면에 보여줄 숫자·날짜 형식
enum Fmt {
    static func km(_ meters: Double) -> String {
        let km = meters / 1000
        return km < 10 ? String(format: "%.2f km", km) : String(format: "%.1f km", km)
    }

    /// m/s → "87" (km/h 숫자만)
    static func speedNumber(_ mps: Double) -> String {
        String(format: "%.0f", max(mps, 0) * 3.6)
    }

    static func kmh(_ mps: Double) -> String {
        "\(speedNumber(mps)) km/h"
    }

    /// 1:23:45 형식
    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(max(seconds, 0))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// 1시간 23분 형식
    static func duration(_ seconds: TimeInterval) -> String {
        let t = Int(max(seconds, 0))
        let h = t / 3600
        let m = (t % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        if m > 0 { return "\(m)분" }
        return "\(t)초"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    static let dateTime = formatter("M월 d일 (E) HH:mm")
    static let date = formatter("yyyy년 M월 d일 (E)")
    static let time = formatter("HH:mm")
    static let month = formatter("yyyy년 M월")
    static let csv = formatter("yyyy-MM-dd HH:mm")
    static let fileStamp = formatter("yyyyMMdd-HHmm")
}
