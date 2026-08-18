//
//  CalendarWeatherKind.swift
//  Mona
//

/// The four conditions the artwork can draw.
enum CalendarWeatherKind: String, Codable, CaseIterable {
    case sunny, cloudy, rain, snow

    var label: String {
        switch self {
        case .sunny: return "晴"
        case .cloudy: return "多云"
        case .rain: return "雨"
        case .snow: return "雪"
        }
    }

    /// WMO codes, which is what Open-Meteo reports.
    ///
    /// Collapsed to four buckets because there are only four icons: drizzle,
    /// freezing rain and showers are all "雨" as far as the artwork is concerned.
    static func fromWMO(_ code: Int) -> CalendarWeatherKind {
        switch code {
        case 0, 1: return .sunny
        case 2, 3, 45, 48: return .cloudy
        case 71...77, 85, 86: return .snow
        case 51...67, 80...82, 95...99: return .rain
        default: return .cloudy
        }
    }
}
