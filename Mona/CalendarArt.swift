//
//  CalendarArt.swift
//  Mona
//

import CoreGraphics
import Foundation
import ImageIO

/// Where every calendar piece goes — looked up, not computed.
///
/// The layout used to be re-derived here: centres and angles measured off twelve
/// reference stickers, plates grown out of the glyphs, the weather card hung off
/// the day's right edge. The offline renderer it was copied from has since moved
/// well past that — the plates and outlines are drawn artwork now rather than
/// dilations, the weather hangs off
/// the weekday tab, and the digits carry per-glyph scale, shift and a spacing
/// floor that stops a wide month from crashing into the day. Keeping a second
/// implementation of all that in Swift meant two things that drift apart.
///
/// So the split moved: **Python works out every placement and ships the table**,
/// and this app looks it up and composites. There are only a few thousand
/// distinct arrangements — twelve months by thirty-one days for the date, and
/// the weekday tab, time-of-day card and weather icon on top — so the whole
/// table is a couple of hundred kilobytes.
struct CalendarLayout: Decodable {
    /// One placed piece. `a` is `[a, b, c, d, tx, ty]` and reads
    /// `canvas = A · assetPixel + T`, in the layout's own canvas; scale the
    /// whole six by `renderWidth / canvasWidth` to draw at any size.
    struct Entry: Decodable {
        let a: [Double]
        /// Flat asset prefix, e.g. `cal-day-7`; the layer suffix goes on the end.
        let g: String
        /// Only the weather carries one: the four corners of the slanted white
        /// square it sits on, in canvas coordinates.
        let card: [[Double]]?

        var matrix: [Double] { a.count >= 6 ? a : [1, 0, 0, 1, 0, 0] }
    }

    /// One of the design's five layers, bottom first. A layer is one colour all
    /// through — that is the premise the whole stacking rests on.
    struct Layer: Decodable {
        let white: Bool
        /// `[element, part]`, e.g. `["day_0", "plate"]`.
        let items: [[String]]
    }

    struct Placements: Decodable {
        /// Keyed `"<month>-<day>"`.
        let date: [String: [String: Entry]]
        /// Keyed `"<d1|d2>|<weekday>"`.
        let week: [String: Entry]
        /// Keyed `"<d1|d2>|<slot>"`.
        let status: [String: Entry]
        /// Keyed `"<d1|d2>|<weekday>|<kind>|<frame>"` — the icon hangs off the
        /// weekday tab, so which weekday it is changes where it lands.
        let weather: [String: Entry]
    }

    let canvas: [Double]
    let assets: [String]
    let stack: [Layer]
    /// part name → file suffix, e.g. `plate` → `-plate`.
    let suffix: [String: String]
    /// Radius that bridges the month's black to the day's black, in canvas
    /// pixels. Absolute rather than a fraction of the width, because the canvas
    /// was widened to stop two-digit months running off the left and the bridge
    /// should not have widened with it.
    let bridgePx: Double
    /// Square brush that seals the hairline between neighbouring plates: wider
    /// under the whites, where the gap between the weather card and the weekday
    /// tab is a good two pixels, narrower under the blacks so the narrow white
    /// slots the design does want stay open.
    let seal: [String: Int]
    let placements: Placements

    var size: CGSize { CGSize(width: canvas[0], height: canvas[1]) }
    var aspect: CGFloat { CGFloat(canvas[0]/canvas[1]) }

    enum CodingKeys: String, CodingKey {
        case canvas, assets, stack, suffix, seal, placements
        case bridgePx = "bridge_px"
    }
}

/// Loads and caches the PNGs and the layout from the app bundle.
///
/// Everything is looked up by a flat, unique name (`cal-day-7-plate`), because a
/// synchronized folder of resources lands flat in the bundle — `Month/4.png` and
/// `Day/4.png` would collide, so the export script names them apart instead.
final class CalendarArt {
    /// Load from a folder instead of the bundle. Only `Tools/RenderCalendar`
    /// sets it, so that the checking tool draws through this very renderer
    /// rather than through a copy of it — the copy is what let the two drift.
    /// Set before first use; the pack is read once.
    nonisolated(unsafe) static var resourceDirectory: String?

    nonisolated(unsafe) static let shared = CalendarArt()

    private var images: [String: CGImage] = [:]
    private var missing: Set<String> = []
    private let lock = NSLock()

    /// Shared by everything that loads a bundled resource, so the checking
    /// tool can point the whole app at a folder instead of a bundle.
    static func url(_ name: String, _ ext: String) -> URL? {
        if let dir = resourceDirectory {
            let u = URL(fileURLWithPath: dir).appendingPathComponent("\(name).\(ext)")
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext,
                               subdirectory: "CalendarResources")
    }

    /// Nil when the art pack is missing, which is the one failure the HUD cannot
    /// paint through — the caller shows nothing rather than a half-drawn design.
    let layout: CalendarLayout?

    private init() {
        guard let url = CalendarArt.url("cal-layout", "json"),
              let data = try? Data(contentsOf: url) else {
            NSLog("Mona calendar: cal-layout.json missing from the bundle")
            layout = nil
            return
        }
        do {
            layout = try JSONDecoder().decode(CalendarLayout.self, from: data)
        } catch {
            // Said out loud rather than swallowed. A field added to the struct
            // but not to the art pack makes decoding throw, and a nil layout
            // draws nothing at all — which looks like the window is broken
            // rather than like the data is.
            NSLog("Mona calendar: cal-layout.json does not match the renderer: \(error)")
            layout = nil
        }
    }

    /// Nil for a name the pack does not carry. Not every group has every layer —
    /// the month digits have no `-text`, the weather icons are a single shape —
    /// so a miss is ordinary and is remembered rather than retried.
    func image(_ name: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = images[name] { return hit }
        if missing.contains(name) { return nil }
        guard let url = CalendarArt.url(name, "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            missing.insert(name)
            return nil
        }
        images[name] = image
        return image
    }

    static func weekKey(_ weekday: Int) -> String {
        // `Calendar` numbers Sunday as 1.
        let keys = ["sunday", "monday", "tuesday", "wednesday",
                    "thursday", "friday", "saturday"]
        return keys[max(0, min(6, weekday - 1))]
    }
}

/// The five times of day the artwork has a card for.
enum CalendarDaySlot: String {
    case dawn, morning, noon, afternoon, night

    /// Boundaries picked to match what the cards say: 早晨 before the working day,
    /// 上午 through the morning, 中午 over lunch, 下午 through the afternoon, 夜晚
    /// once it is dark.
    static func forHour(_ hour: Int) -> CalendarDaySlot {
        switch hour {
        case 5..<9: return .dawn
        case 9..<11: return .morning
        case 11..<14: return .noon
        case 14..<18: return .afternoon
        default: return .night
        }
    }
}
