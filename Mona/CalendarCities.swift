//
//  CalendarCities.swift
//  Mona
//

import Foundation

/// Somewhere to fetch the weather for.
///
/// A list rather than a coordinate field. Latitude and longitude are the one
/// thing the weather needs and the one thing nobody knows off the top of their
/// head, and an accessory app that opens by asking for your location is a
/// strange thing to be prompted by. So the default is a city — and the system is
/// only ever asked where you are if you go and pick "当前位置" yourself.
struct CalendarCity: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    /// The one entry that is not a place: follow the machine. Picking it is what
    /// authorises the location prompt.
    static let currentID = "current"
    static let defaultID = "shanghai"

    static let current = CalendarCity(id: currentID, name: "当前位置",
                                      latitude: 0, longitude: 0)

    struct Group: Identifiable {
        let id: String
        let title: String
        let cities: [CalendarCity]
    }

    /// The shortlist the picker shows before you type anything. Deliberately
    /// short: it is a shortcut for the common case, not a directory — anywhere
    /// else is a search away, out of a table of twenty-six thousand.
    static let groups: [Group] = [
        Group(id: "cn", title: "中国", cities: [
            CalendarCity(id: "beijing", name: "北京", latitude: 39.9042, longitude: 116.4074),
            CalendarCity(id: "shanghai", name: "上海", latitude: 31.2304, longitude: 121.4737),
            CalendarCity(id: "guangzhou", name: "广州", latitude: 23.1291, longitude: 113.2644),
            CalendarCity(id: "shenzhen", name: "深圳", latitude: 22.5431, longitude: 114.0579),
            CalendarCity(id: "hangzhou", name: "杭州", latitude: 30.2741, longitude: 120.1551),
            CalendarCity(id: "chengdu", name: "成都", latitude: 30.5728, longitude: 104.0668),
            CalendarCity(id: "chongqing", name: "重庆", latitude: 29.5630, longitude: 106.5516),
            CalendarCity(id: "wuhan", name: "武汉", latitude: 30.5928, longitude: 114.3055),
            CalendarCity(id: "nanjing", name: "南京", latitude: 32.0603, longitude: 118.7969),
            CalendarCity(id: "xian", name: "西安", latitude: 34.3416, longitude: 108.9398)
        ]),
        Group(id: "us", title: "美国", cities: [
            CalendarCity(id: "newyork", name: "纽约", latitude: 40.7128, longitude: -74.0060),
            CalendarCity(id: "losangeles", name: "洛杉矶", latitude: 34.0522, longitude: -118.2437),
            CalendarCity(id: "sanfrancisco", name: "旧金山", latitude: 37.7749, longitude: -122.4194),
            CalendarCity(id: "seattle", name: "西雅图", latitude: 47.6062, longitude: -122.3321),
            CalendarCity(id: "chicago", name: "芝加哥", latitude: 41.8781, longitude: -87.6298)
        ]),
        Group(id: "capitals", title: "其他", cities: [
            CalendarCity(id: "tokyo", name: "东京", latitude: 35.6762, longitude: 139.6503),
            CalendarCity(id: "seoul", name: "首尔", latitude: 37.5665, longitude: 126.9780),
            CalendarCity(id: "london", name: "伦敦", latitude: 51.5074, longitude: -0.1278),
            CalendarCity(id: "paris", name: "巴黎", latitude: 48.8566, longitude: 2.3522),
            CalendarCity(id: "berlin", name: "柏林", latitude: 52.5200, longitude: 13.4050),
            CalendarCity(id: "rome", name: "罗马", latitude: 41.9028, longitude: 12.4964),
            CalendarCity(id: "canberra", name: "堪培拉", latitude: -35.2809, longitude: 149.1300),
            CalendarCity(id: "moscow", name: "莫斯科", latitude: 55.7558, longitude: 37.6173)
        ])
    ]

    static let all: [CalendarCity] = groups.flatMap(\.cities)

    /// Falls back to the default rather than to nowhere: a key left over from an
    /// older build should show Shanghai's weather, not none at all.
    static func named(_ id: String) -> CalendarCity? {
        if id == currentID { return current }
        return all.first { $0.id == id } ?? all.first { $0.id == defaultID }
    }
}

/// What the preference actually holds, and how it is written down.
///
/// It used to be a city id out of the shortlist. That stopped working the moment
/// anywhere could be searched: a place found in the table has no id, so the
/// choice has to carry its own coordinates. Stored as one string rather than
/// three keys so that reading it is atomic — a half-updated pair of numbers
/// would be a real place nobody picked.
enum CalendarChoice {
    case here                                   // 当前位置
    case fixed(name: String, latitude: Double, longitude: Double)

    static func encode(_ name: String, _ lat: Double, _ lon: Double) -> String {
        // Name last, and split with a limit, so a name containing the separator
        // survives the round trip.
        "\(lat)|\(lon)|\(name)"
    }

    static func decode(_ raw: String) -> CalendarChoice {
        if raw == CalendarCity.currentID { return .here }
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3, let lat = Double(parts[0]), let lon = Double(parts[1]) {
            return .fixed(name: String(parts[2]), latitude: lat, longitude: lon)
        }
        // An id from an older build, or nonsense. Either way the shortlist knows
        // what to do — and its fallback is Shanghai, not nothing.
        let city = CalendarCity.named(raw) ?? CalendarCity.named(CalendarCity.defaultID)!
        return .fixed(name: city.name, latitude: city.latitude, longitude: city.longitude)
    }

    var name: String {
        switch self {
        case .here: return CalendarCity.current.name
        case .fixed(let name, _, _): return name
        }
    }
}

/// One result out of the searchable table.
struct CalendarPlace: Identifiable, Hashable {
    /// What to show. `name` is the Chinese name where GeoNames has one and the
    /// local name otherwise; `detail` is "省州 · 国家", there only to tell the
    /// two Portlands apart.
    let name: String
    let ascii: String
    let state: String
    let country: String        // ISO code; the system localises it
    let latitude: Double
    let longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }

    var detail: String {
        let region = Locale.current.localizedString(forRegionCode: country) ?? country
        return state.isEmpty ? region : "\(state) · \(region)"
    }
}

/// The searchable table: every city over fifteen thousand people, about
/// twenty-six thousand of them, shipped in the bundle.
///
/// Local rather than a geocoding request per keystroke. The data is the same —
/// Open-Meteo's geocoding is GeoNames underneath — but this way a result appears
/// on the keystroke rather than after a round trip, it works with no network,
/// there is no rate limit to back off from, and what you type stays here.
///
/// The file is pre-sorted by population, which is the whole ranking scheme: a
/// scan that stops at twenty hits returns the twenty biggest matches without
/// sorting anything.
@MainActor
enum CalendarPlaceTable {
    private static var rows: [CalendarPlace] = []
    private static var loaded = false

    /// Parsed once, lazily — nobody pays for it unless they open the picker.
    private static func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = CalendarArt.url("cal-cities", "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            NSLog("Mona calendar: cal-cities.tsv missing; only the shortlist is searchable")
            return
        }
        rows.reserveCapacity(30_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 6, let lat = Double(f[4]), let lon = Double(f[5])
            else { continue }
            rows.append(CalendarPlace(name: String(f[0]), ascii: String(f[1]),
                                      state: String(f[2]), country: String(f[3]),
                                      latitude: lat, longitude: lon))
        }
    }

    /// Substring, case- and accent-insensitive, over both the local name and the
    /// latin one. The latin column is why "zhuhai" finds 珠海 without anyone
    /// having to build a pinyin index — for Chinese cities GeoNames' ascii name
    /// *is* the pinyin.
    ///
    /// Ranked exact, then prefix, then substring; within each, by population,
    /// which the file order already gives.
    static func search(_ raw: String, limit: Int = 20) -> [CalendarPlace] {
        load()
        let q = raw.folding(options: [.caseInsensitive, .diacriticInsensitive],
                            locale: .current)
            .trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var exact: [CalendarPlace] = []
        var prefix: [CalendarPlace] = []
        var loose: [CalendarPlace] = []
        for row in rows {
            let a = row.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: .current)
            let b = row.ascii.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                      locale: .current)
            if a == q || b == q {
                exact.append(row)
            } else if a.hasPrefix(q) || b.hasPrefix(q) {
                prefix.append(row)
            } else if a.contains(q) || b.contains(q) {
                loose.append(row)
            } else {
                continue
            }
            // Enough of every rank to fill the list even if one of them is empty.
            if exact.count >= limit { break }
        }
        return Array((exact + prefix + loose).prefix(limit))
    }
}
