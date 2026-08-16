//
//  CalendarWeather.swift
//  Mona
//

import Combine
import CoreLocation
import Foundation

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

/// Where to look up the weather for.
private struct Coordinate {
    let latitude: Double
    let longitude: Double
}

/// Fetches the current condition and keeps the last good answer.
///
/// Deliberately forgiving: the HUD is a decoration, so every failure path ends at
/// "keep showing what we last knew, try again later" rather than at an error. A
/// machine that has been offline since launch shows 晴, which is the least
/// alarming thing to be wrong about.
@MainActor
final class CalendarWeatherSource: NSObject, ObservableObject {
    @Published private(set) var kind: CalendarWeatherKind = .sunny
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var placeName: String?

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var inFlight = false
    private var coordinate: Coordinate?

    /// Half an hour. Conditions do not change faster than the icon can show, and
    /// a desktop toy has no business polling harder than that.
    private let refreshInterval: TimeInterval = 30 * 60

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let stored = UserDefaults.standard.string(forKey: PetPreferences.calendarWeatherKey),
           let restored = CalendarWeatherKind(rawValue: stored) {
            kind = restored
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 60
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight = false } }
            let where_ = await self.resolveLocation()
            guard let where_ else { return }
            guard let code = await Self.fetchWeatherCode(where_) else { return }
            await MainActor.run {
                self.kind = .fromWMO(code)
                self.lastUpdated = Date()
                UserDefaults.standard.set(self.kind.rawValue,
                                          forKey: PetPreferences.calendarWeatherKey)
            }
        }
    }

    // MARK: - location

    /// The chosen city, or — only if that choice is "当前位置" — the machine.
    ///
    /// The city is checked first and returns immediately, so a default install
    /// never reaches CoreLocation and never triggers its prompt. Asking for
    /// someone's location is a thing to be opted into, not something a desktop
    /// toy does on first launch to decide which of four icons to draw.
    private func resolveLocation() async -> Coordinate? {
        let raw = UserDefaults.standard.string(forKey: PetPreferences.calendarCityKey)
            ?? CalendarCity.defaultID
        if case .fixed(let name, let lat, let lon) = CalendarChoice.decode(raw) {
            await MainActor.run { self.placeName = name }
            return Coordinate(latitude: lat, longitude: lon)
        }
        if let cached = coordinate { return cached }
        if let fix = await requestCoreLocation() {
            coordinate = fix
            await MainActor.run { self.placeName = "当前位置" }
            return fix
        }
        // Location can be off, denied, or simply never answer. Falling back to
        // the IP address keeps "当前位置" meaning roughly what it says instead of
        // leaving the icon frozen on whatever it last showed.
        if let ip = await Self.fetchIPLocation() {
            coordinate = ip.0
            await MainActor.run { self.placeName = ip.1 }
            return ip.0
        }
        return nil
    }

    /// Forget where we thought we were and look again. Called when the city
    /// changes, since the cached fix belongs to the old choice.
    func locationChanged() {
        coordinate = nil
        refresh()
    }

    private var locationContinuation: CheckedContinuation<Coordinate?, Never>?

    private func requestCoreLocation() async -> Coordinate? {
        let status = manager.authorizationStatus
        guard status != .denied && status != .restricted else { return nil }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { continuation in
            // Only one request in flight; a second caller gets nil rather than
            // stranding the first one's continuation.
            guard locationContinuation == nil else {
                continuation.resume(returning: nil)
                return
            }
            locationContinuation = continuation
            manager.requestLocation()
            // CoreLocation can simply never call back — a Mac with location
            // services off answers nothing at all — so the wait is bounded.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finishLocation(nil)
            }
        }
    }

    private func finishLocation(_ value: Coordinate?) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: value)
    }

    // MARK: - network

    private static func fetchWeatherCode(_ at: Coordinate) async -> Int? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", at.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", at.longitude)),
            URLQueryItem(name: "current", value: "weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }
        struct Response: Decodable {
            struct Current: Decodable { let weather_code: Int }
            let current: Current
        }
        guard let data = await get(url) else { return nil }
        return try? JSONDecoder().decode(Response.self, from: data).current.weather_code
    }

    private static func fetchIPLocation() async -> (Coordinate, String)? {
        guard let url = URL(string: "https://ipapi.co/json/"),
              let data = await get(url) else { return nil }
        struct Response: Decodable {
            let latitude: Double?
            let longitude: Double?
            let city: String?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let lat = r.latitude, let lon = r.longitude else { return nil }
        return (Coordinate(latitude: lat, longitude: lon), r.city ?? "IP 定位")
    }

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mona/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}

extension CalendarWeatherSource: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let fix = Coordinate(latitude: last.coordinate.latitude,
                             longitude: last.coordinate.longitude)
        Task { @MainActor in self.finishLocation(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorized ||
                manager.authorizationStatus == .authorizedAlways {
                self.refresh()
            }
        }
    }
}
