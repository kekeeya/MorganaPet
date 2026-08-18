//
//  CalendarHUDRenderer.swift
//  Mona
//

import CoreGraphics
import Foundation
#if !WIDGET_EXTENSION
import AppKit
#endif

/// What the HUD is showing.
struct CalendarHUDContent: Equatable {
    var month: Int
    var day: Int
    var weekday: Int          // `Calendar` numbering, Sunday == 1
    var weather: CalendarWeatherKind
    var slot: CalendarDaySlot
    /// Which of the weather icon's three drawings to use. They are meant to be
    /// cycled 1-2-3; they are drawn in register, so only the icon moves.
    var frame: Int = 1

    static func now(weather: CalendarWeatherKind) -> CalendarHUDContent {
        let parts = Calendar.current.dateComponents(
            [.month, .day, .weekday, .hour], from: Date())
        return CalendarHUDContent(
            month: parts.month ?? 1,
            day: parts.day ?? 1,
            weekday: parts.weekday ?? 1,
            weather: weather,
            slot: .forHour(parts.hour ?? 12)
        )
    }
}

/// Draws the date sticker by stacking the design's five layers.
///
/// Bottom to top: every white backing, the weather icon, every black plate, every
/// white glyph, then the lettering. Not piece by piece — stacking whole pieces
/// always loses one of them, because the weekday tab and the date overlap and
/// whichever goes second buries the other. Layer by layer neither can: no
/// backing is ever above a glyph, and two whites that meet are the same white,
/// so they simply become one shape. That is what the reference stickers do.
///
/// Where each piece goes is not worked out here — it is read out of
/// `cal-layout.json`, which the offline renderer's export step writes. See
/// `CalendarLayout` for why.
enum CalendarHUDRenderer {
    private struct RenderedFrame {
        let image: CGImage
        let pointSize: CGSize
    }

    static var aspect: CGFloat { CalendarArt.shared.layout?.aspect ?? 640/500 }

#if !WIDGET_EXTENSION
    static func render(_ content: CalendarHUDContent,
                       width: CGFloat, scale: CGFloat) -> NSImage? {
        renderFrames(content, frames: [content.frame],
                     width: width, scale: scale).first
    }
#endif

    static func renderCG(_ content: CalendarHUDContent,
                         width: CGFloat, scale: CGFloat) -> CGImage? {
        makeFrames(content, frames: [content.frame],
                   width: width, scale: scale).first?.image
    }

#if !WIDGET_EXTENSION
    /// Several weather frames of the same sticker at once.
    ///
    /// Only the bottom two layers have anything to do with the weather — the
    /// icon, and the white square under it. The black plates, the white glyphs
    /// and the lettering are identical in all three, and those carry the whole
    /// morphology bill (a flood fill and two separable closes each). Rendering
    /// the frames one at a time paid that three times over.
    static func renderFrames(_ content: CalendarHUDContent, frames: [Int],
                             width: CGFloat, scale: CGFloat) -> [NSImage] {
        makeFrames(content, frames: frames, width: width, scale: scale).map {
            NSImage(cgImage: $0.image, size: $0.pointSize)
        }
    }
#endif

    private static func makeFrames(_ content: CalendarHUDContent, frames: [Int],
                                   width: CGFloat, scale: CGFloat) -> [RenderedFrame] {
        guard let layout = CalendarArt.shared.layout, !frames.isEmpty else { return [] }
        let k = width*scale/CGFloat(layout.canvas[0])
        let w = Int((CGFloat(layout.canvas[0])*k).rounded())
        let h = Int((CGFloat(layout.canvas[1])*k).rounded())
        guard w > 8, h > 8 else { return [] }

        let day = String(content.day)
        let variant = day.count >= 2 ? "d2" : "d1"
        let week = CalendarArt.weekKey(content.weekday)

        // Assigning nil removes the key, so a piece the table has no row for
        // simply is not drawn — which is what should happen for, say, the tens
        // digit of a one-digit month.
        var put = layout.placements.date["\(content.month)-\(content.day)"] ?? [:]
        put["week"] = layout.placements.week["\(variant)|\(week)"]
        put["status"] = layout.placements.status["\(variant)|\(content.slot.rawValue)"]
        guard !put.isEmpty else { return [] }

        var shared: [Int: CalendarRaster.Field] = [:]
        var out: [RenderedFrame] = []
        let point = CGSize(width: width, height: width/aspect)
        for raw in frames {
            let frame = min(3, max(1, raw))
            put["weather"] = layout.placements.weather[
                "\(variant)|\(week)|\(content.weather.rawValue)|\(frame)"]

            // The card is four corners rather than artwork; it comes along with
            // the weather placement because it is sized and turned off the icon.
            var card: CalendarRaster.Field?
            if let points = put["weather"]?.card, points.count == 4 {
                card = CalendarRaster.quad(points.map {
                    CGPoint(x: CGFloat($0[0])*k, y: CGFloat($0[1])*k) }, w: w, h: h)
            }

            var rgb = [Float](repeating: 0, count: w*h)
            var alpha = [Float](repeating: 0, count: w*h)
            for (index, layer) in layout.stack.enumerated() {
                let movesWithWeather = layer.items.contains { $0.first == "weather" }
                var cov: CalendarRaster.Field
                if !movesWithWeather, let cached = shared[index] {
                    cov = cached
                } else {
                    cov = finish(layer, put: put, card: card, layout: layout,
                                 k: k, w: w, h: h)
                    if !movesWithWeather { shared[index] = cov }
                }
                if cov.isEmpty { continue }
                let tone: Float = layer.white ? 1 : 0
                for i in 0..<(w*h) {
                    let c = cov.v[i]
                    guard c > 0 else { continue }
                    rgb[i] = tone*c + rgb[i]*(1 - c)
                    alpha[i] = c + alpha[i]*(1 - c)
                }
            }
            if let img = image(rgb: rgb, alpha: alpha, w: w, h: h) {
                out.append(RenderedFrame(image: img, pointSize: point))
            }
        }
        return out
    }

    /// One layer's finished coverage: the pieces drawn, then the fills and seals
    /// the design asks of that particular layer.
    private static func finish(_ layer: CalendarLayout.Layer,
                               put: [String: CalendarLayout.Entry],
                               card: CalendarRaster.Field?,
                               layout: CalendarLayout,
                               k: CGFloat, w: Int, h: Int) -> CalendarRaster.Field {
        var cov = coverage(layer, put: put, card: card, layout: layout,
                           k: k, w: w, h: h)
        if !layer.white {
            fillBetweenPlates(&cov, layer, put: put, layout: layout,
                              k: k, w: w, h: h)
        }
        if cov.isEmpty { return cov }
        let parts = Set(layer.items.compactMap { $0.count > 1 ? $0[1] : nil })
        // The bottom white is one continuous sheet in the design; anything
        // enclosed by it is sheet too. Without this the seam where the weather
        // card meets the weekday tab's backing shows as a hairline of wallpaper
        // — too wide for the square brush below to close, and open at one end so
        // it is not a hole in the layer's own sense.
        if layer.white && !parts.isDisjoint(with: ["under", "card"]) {
            let sheet = CalendarRaster.holes(cov.mask(), w: w, h: h)
            cov.raise(CalendarRaster.grow(sheet, w: w, h: h))
        }
        // Sealed only where the layer has backings. A lettering layer must not
        // be: the white slots inside a Chinese character are two or three pixels
        // wide and the brush would weld them shut.
        if !parts.isDisjoint(with: ["plate", "under", "ink"]) {
            let side = layer.white ? (layout.seal["white"] ?? 5)
                                   : (layout.seal["black"] ?? 3)
            // The brush is a radius either side of the pixel, so it has to stay
            // odd when the canvas is scaled up — rounding the whole side instead
            // lands on 6 at 2x and seals half a pixel wider than the offline
            // renderer does.
            let r = max(1, Int((CGFloat(side/2)*k).rounded()))
            let solid = cov.mask()
            let sealed = CalendarRaster.closeBox(solid, w: w, h: h, side: 2*r + 1)
            var gained = CalendarRaster.Mask(repeating: 0, count: solid.count)
            for i in 0..<solid.count where sealed[i] != 0 && solid[i] == 0 {
                gained[i] = 1
            }
            cov.raise(gained)
        }
        return cov
    }

    // MARK: - one layer

    private static func coverage(_ layer: CalendarLayout.Layer,
                                 put: [String: CalendarLayout.Entry],
                                 card: CalendarRaster.Field?,
                                 layout: CalendarLayout,
                                 k: CGFloat, w: Int, h: Int) -> CalendarRaster.Field {
        var pieces: [(CGImage, CGAffineTransform)] = []
        var withCard: CalendarRaster.Field?
        for item in layer.items where item.count >= 2 {
            let (name, part) = (item[0], item[1])
            if part == "card" {
                withCard = card
                continue
            }
            guard let entry = put[name],
                  let image = asset(entry, part, layout) else { continue }
            pieces.append((image, transform(entry, image, k: k, h: h)))
        }
        var field = CalendarRaster.rasterise(pieces, w: w, h: h)
        if let c = withCard { field.add(c) }
        return field
    }

    /// The pockets the four black plates ring — month, slash, day and weekday —
    /// filled in.
    ///
    /// Their blacks are one shape in the design, so any white the four of them
    /// close around is black too. Bridging first, and only when it actually joins
    /// separate plates: a close that merely fattens one blob is a fatter plate,
    /// not a bridge, and the design's plate is not fatter.
    private static func fillBetweenPlates(_ cov: inout CalendarRaster.Field,
                                          _ layer: CalendarLayout.Layer,
                                          put: [String: CalendarLayout.Entry],
                                          layout: CalendarLayout,
                                          k: CGFloat, w: Int, h: Int) {
        var pieces: [(CGImage, CGAffineTransform)] = []
        for item in layer.items where item.count >= 2 {
            let (name, part) = (item[0], item[1])
            guard part == "plate" || part == "ink",
                  let entry = put[name],
                  let image = asset(entry, part, layout) else { continue }
            pieces.append((image, transform(entry, image, k: k, h: h)))
        }
        guard !pieces.isEmpty else { return }
        var solid = CalendarRaster.rasterise(pieces, w: w, h: h).mask()
        guard solid.contains(where: { $0 != 0 }) else { return }
        // Count first. Bridging costs two full distance transforms — by far the
        // most expensive thing in the whole composite — and it can only help if
        // the plates are in more than one piece to begin with. With the drawn
        // artwork they nearly always already overlap into one, so this skips it
        // outright rather than computing a close and then discovering it changed
        // nothing.
        if CalendarRaster.pieces(solid, w: w, h: h) > 1 {
            let radius = Float(max(2, (CGFloat(layout.bridgePx)*k).rounded()))
            let bridged = CalendarRaster.close(solid, w: w, h: h, radius: radius)
            if CalendarRaster.pieces(bridged, w: w, h: h)
                < CalendarRaster.pieces(solid, w: w, h: h) {
                var gained = CalendarRaster.Mask(repeating: 0, count: solid.count)
                for i in 0..<solid.count where bridged[i] != 0 && solid[i] == 0 {
                    gained[i] = 1
                }
                cov.raise(gained)
                solid = bridged
            }
        }
        // Grown by a pixel: the ring where the plates fade out sits between two
        // blacks once the pocket is filled, and left partial it shows the white
        // sheet underneath as a hairline.
        let pocket = CalendarRaster.holes(solid, w: w, h: h)
        cov.raise(CalendarRaster.grow(pocket, w: w, h: h))
    }

    private static func asset(_ entry: CalendarLayout.Entry, _ part: String,
                              _ layout: CalendarLayout) -> CGImage? {
        // `icon` is the weather, which is a single shape with no suffix.
        let suffix = part == "icon" ? "" : (layout.suffix[part] ?? "")
        return CalendarArt.shared.image(entry.g + suffix)
    }

    /// `canvas = A · assetPixel + T`, converted for CoreGraphics.
    ///
    /// Two conversions in one: the six numbers are for the layout's own canvas
    /// so they all scale by `k`, and they were fitted with y running down while
    /// CoreGraphics runs it up. An image drawn into `(0, 0, w, h)` lands with its
    /// first row at the top of that rect, so the asset's own y is flipped too —
    /// which is where the `+ b·h` and `- d·h` come from.
    private static func transform(_ entry: CalendarLayout.Entry, _ image: CGImage,
                                  k: CGFloat, h: Int) -> CGAffineTransform {
        let m = entry.matrix
        let a = CGFloat(m[0])*k, b = CGFloat(m[1])*k
        let c = CGFloat(m[2])*k, d = CGFloat(m[3])*k
        let tx = CGFloat(m[4])*k, ty = CGFloat(m[5])*k
        let ih = CGFloat(image.height)
        return CGAffineTransform(a: a, b: -c, c: -b, d: d,
                                 tx: tx + b*ih, ty: CGFloat(h) - ty - d*ih)
    }

    // MARK: - out

    /// The accumulated colour is premultiplied; a PNG-style straight-alpha image
    /// is not. Skipping the divide puts a grey rim right round the sticker: on
    /// the white outline's antialiased edge the coverage is a half, and a half
    /// stored straight is mid-grey rather than white at half opacity.
    private static func image(rgb: [Float], alpha: [Float], w: Int, h: Int) -> CGImage? {
        var buffer = [UInt8](repeating: 0, count: w*h*4)
        for i in 0..<(w*h) {
            let a = alpha[i]
            let v: UInt8 = a > 1e-4
                ? UInt8(max(0, min(255, (rgb[i]/a*255).rounded())))
                : 0
            buffer[i*4] = v
            buffer[i*4 + 1] = v
            buffer[i*4 + 2] = v
            buffer[i*4 + 3] = UInt8(max(0, min(255, (a*255).rounded())))
        }
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else {
            return nil
        }
        return CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
    }
}
