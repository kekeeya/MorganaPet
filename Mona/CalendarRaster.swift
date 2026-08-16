//
//  CalendarRaster.swift
//  Mona
//

import CoreGraphics
import Foundation

/// The bitmap work the calendar's five-layer composite needs and CoreImage does
/// not do: filling enclosed holes, counting how many separate pieces a shape is
/// in, and closing with an exact disc.
///
/// The offline renderer these numbers came from uses scipy. Matching it matters
/// more than reusing what is already here —
/// `CIMorphologyMaximum` blurs at the edges, and a plate that is a pixel fatter
/// than the offline one shows up as a grey rim once the white outline underneath
/// it peeks through.
///
/// Written against raw buffers rather than `[Bool]` and closures. That is not
/// premature: a sticker is well over a million pixels and every one of these
/// passes touches all of them, and an unoptimised build — which is what running
/// from Xcode gives you — pays for a bounds check and a captured-array retain on
/// each. The first version took eighteen seconds a frame that way, against a
/// quarter of a second optimised, and froze the app solid.
enum CalendarRaster {

    /// A binary mask: 1 or 0 per pixel, row-major with y running down.
    typealias Mask = [UInt8]

    /// A coverage map: one value per pixel, 0…1, same layout.
    struct Field {
        let w: Int
        let h: Int
        var v: [Float]

        init(w: Int, h: Int) {
            self.w = w
            self.h = h
            v = [Float](repeating: 0, count: max(0, w*h))
        }

        var isEmpty: Bool {
            v.withUnsafeBufferPointer { p in
                for x in p where x > 0 { return false }
                return true
            }
        }

        func mask(_ t: Float = 0.5) -> Mask {
            let n = v.count
            var out = Mask(repeating: 0, count: n)
            v.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<n { dst[i] = src[i] > t ? 1 : 0 }
                }
            }
            return out
        }

        /// `cov = max(cov, extra)`, which is how the offline renderer folds a
        /// filled hole or a sealed seam back into the layer.
        mutating func raise(_ extra: Mask) {
            let n = min(v.count, extra.count)
            v.withUnsafeMutableBufferPointer { dst in
                extra.withUnsafeBufferPointer { src in
                    for i in 0..<n where src[i] != 0 { dst[i] = 1 }
                }
            }
        }

        /// `cov = min(1, cov + other)` — the union used inside a layer.
        mutating func add(_ other: Field) {
            let n = min(v.count, other.v.count)
            v.withUnsafeMutableBufferPointer { dst in
                other.v.withUnsafeBufferPointer { src in
                    for i in 0..<n { dst[i] = min(1, dst[i] + src[i]) }
                }
            }
        }
    }

    // MARK: - rasterising

    /// Draws pieces into one coverage map.
    ///
    /// The union inside a layer is **min(1, a + b)**, not `1-(1-a)(1-b)` — hence
    /// `.plusLighter`. Where two whites merely touch, each covers half the
    /// boundary pixel; the multiplicative union gives 0.75 there and leaves a
    /// quarter-transparent hairline down the join, which reads as a grey line
    /// over the wallpaper.
    ///
    /// Only the alpha channel is read, so it does not matter that some artwork is
    /// black (the plates) and some white (the glyphs) — the layer's colour is a
    /// property of the layer, not of the piece.
    static func rasterise(_ pieces: [(CGImage, CGAffineTransform)],
                          w: Int, h: Int) -> Field {
        var out = Field(w: w, h: h)
        guard w > 0, h > 0, !pieces.isEmpty else { return out }
        let bytesPerRow = w*4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow*h)
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.interpolationQuality = .high
            for (image, m) in pieces {
                ctx.saveGState()
                ctx.setBlendMode(.plusLighter)
                ctx.concatenate(m)
                ctx.draw(image, in: CGRect(x: 0, y: 0,
                                           width: image.width, height: image.height))
                ctx.restoreGState()
            }
        }
        readAlpha(buffer, into: &out, w: w, h: h)
        return out
    }

    /// Fills a convex quadrilateral — the slanted white square the weather icon
    /// sits on. Kept as four corners rather than artwork because the four sharp
    /// corners are the whole shape, and a bitmap of it arrived with a rounded
    /// halo and a crooked crop.
    static func quad(_ points: [CGPoint], w: Int, h: Int) -> Field {
        var out = Field(w: w, h: h)
        guard points.count == 4, w > 0, h > 0 else { return out }
        let bytesPerRow = w*4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow*h)
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.beginPath()
            ctx.move(to: CGPoint(x: points[0].x, y: CGFloat(h) - points[0].y))
            for p in points.dropFirst() {
                ctx.addLine(to: CGPoint(x: p.x, y: CGFloat(h) - p.y))
            }
            ctx.closePath()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillPath()
        }
        readAlpha(buffer, into: &out, w: w, h: h)
        return out
    }

    /// A bitmap context draws with y up but stores the top scanline first, so
    /// memory row r is already row r of a y-down image. The flip happens in the
    /// transform that placed the pieces, not here.
    private static func readAlpha(_ buffer: [UInt8], into out: inout Field,
                                  w: Int, h: Int) {
        let bytesPerRow = w*4
        buffer.withUnsafeBufferPointer { src in
            out.v.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let row = y*bytesPerRow
                    let line = y*w
                    for x in 0..<w {
                        dst[line + x] = Float(src[row + x*4 + 3])*(1.0/255.0)
                    }
                }
            }
        }
    }

    // MARK: - morphology

    /// Everything enclosed by `solid` that is not `solid` itself.
    ///
    /// Flood from the border through the background: what the flood cannot reach
    /// is inside. This is what blackens the pockets the four plates ring —
    /// month, slash, day and weekday are drawn as separate pieces, and in the
    /// design their blacks are one shape with no white showing through.
    static func holes(_ solid: Mask, w: Int, h: Int) -> Mask {
        let n = w*h
        var out = Mask(repeating: 0, count: n)
        var stack = [Int](repeating: 0, count: n)
        var top = 0
        solid.withUnsafeBufferPointer { s in
        out.withUnsafeMutableBufferPointer { seen in
        stack.withUnsafeMutableBufferPointer { st in
            // `seen` doubles as the outside marker while flooding, then is
            // inverted into the answer — one buffer instead of two. The pushes
            // are written out rather than put in a nested function: there are
            // four per pixel, and a closure over the stack is heap-boxed in an
            // unoptimised build, which is most of where the frame time went.
            for x in 0..<w {
                if s[x] == 0 && seen[x] == 0 { seen[x] = 1; st[top] = x; top += 1 }
                let j = (h - 1)*w + x
                if s[j] == 0 && seen[j] == 0 { seen[j] = 1; st[top] = j; top += 1 }
            }
            for y in 0..<h {
                let a = y*w, b = y*w + w - 1
                if s[a] == 0 && seen[a] == 0 { seen[a] = 1; st[top] = a; top += 1 }
                if s[b] == 0 && seen[b] == 0 { seen[b] = 1; st[top] = b; top += 1 }
            }
            while top > 0 {
                top -= 1
                let i = st[top]
                let x = i % w
                if x > 0 {
                    let j = i - 1
                    if s[j] == 0 && seen[j] == 0 { seen[j] = 1; st[top] = j; top += 1 }
                }
                if x < w - 1 {
                    let j = i + 1
                    if s[j] == 0 && seen[j] == 0 { seen[j] = 1; st[top] = j; top += 1 }
                }
                if i >= w {
                    let j = i - w
                    if s[j] == 0 && seen[j] == 0 { seen[j] = 1; st[top] = j; top += 1 }
                }
                if i < n - w {
                    let j = i + w
                    if s[j] == 0 && seen[j] == 0 { seen[j] = 1; st[top] = j; top += 1 }
                }
            }
            for i in 0..<n { seen[i] = (s[i] == 0 && seen[i] == 0) ? 1 : 0 }
        }}}
        return out
    }

    /// How many separate pieces a shape is in. Only ever compared before and
    /// after a bridging close, to tell "this joined things up" from "this just
    /// fattened one blob".
    static func pieces(_ solid: Mask, w: Int, h: Int) -> Int {
        let n = w*h
        var seen = Mask(repeating: 0, count: n)
        var stack = [Int](repeating: 0, count: n)
        var count = 0
        solid.withUnsafeBufferPointer { s in
        seen.withUnsafeMutableBufferPointer { m in
        stack.withUnsafeMutableBufferPointer { st in
            var top = 0
            for start in 0..<n where s[start] != 0 && m[start] == 0 {
                count += 1
                m[start] = 1
                st[top] = start
                top += 1
                while top > 0 {
                    top -= 1
                    let i = st[top]
                    let x = i % w
                    if x > 0 {
                        let j = i - 1
                        if s[j] != 0 && m[j] == 0 { m[j] = 1; st[top] = j; top += 1 }
                    }
                    if x < w - 1 {
                        let j = i + 1
                        if s[j] != 0 && m[j] == 0 { m[j] = 1; st[top] = j; top += 1 }
                    }
                    if i >= w {
                        let j = i - w
                        if s[j] != 0 && m[j] == 0 { m[j] = 1; st[top] = j; top += 1 }
                    }
                    if i < n - w {
                        let j = i + w
                        if s[j] != 0 && m[j] == 0 { m[j] = 1; st[top] = j; top += 1 }
                    }
                }
            }
        }}}
        return count
    }

    /// Squared euclidean distance to the nearest set pixel, by the two-pass
    /// separable transform. An exact disc of any radius comes out of one of
    /// these, which a repeated 3×3 brush does not — and the bridge radius is
    /// nineteen pixels at the design canvas, far too big to fake.
    static func distance2(_ from: Mask, w: Int, h: Int, invert: Bool = false)
        -> [Float] {
        let n = w*h
        let far = Float(w*w + h*h)*4
        var d = [Float](repeating: 0, count: n)
        let m = max(w, h)
        var f = [Float](repeating: 0, count: m)
        var dd = [Float](repeating: 0, count: m)
        var vpos = [Int](repeating: 0, count: m)
        var z = [Float](repeating: 0, count: m + 1)

        from.withUnsafeBufferPointer { src in
            d.withUnsafeMutableBufferPointer { dst in
            f.withUnsafeMutableBufferPointer { f in
            dd.withUnsafeMutableBufferPointer { dd in
            vpos.withUnsafeMutableBufferPointer { vpos in
            z.withUnsafeMutableBufferPointer { z in
                for i in 0..<n {
                    let on = invert ? (src[i] == 0) : (src[i] != 0)
                    dst[i] = on ? 0 : far
                }
                @inline(__always) func pass(_ count: Int) {
                    var k = 0
                    vpos[0] = 0
                    z[0] = -far
                    z[1] = far
                    for q in 1..<count {
                        var s = Float(0)
                        while true {
                            let p = vpos[k]
                            s = ((f[q] + Float(q*q)) - (f[p] + Float(p*p)))
                                / Float(2*(q - p))
                            if s <= z[k] && k > 0 { k -= 1 } else { break }
                        }
                        k += 1
                        vpos[k] = q
                        z[k] = s
                        z[k + 1] = far
                    }
                    k = 0
                    for q in 0..<count {
                        while z[k + 1] < Float(q) { k += 1 }
                        let p = vpos[k]
                        dd[q] = Float((q - p)*(q - p)) + f[p]
                    }
                }
                for x in 0..<w {
                    for y in 0..<h { f[y] = dst[y*w + x] }
                    pass(h)
                    for y in 0..<h { dst[y*w + x] = dd[y] }
                }
                for y in 0..<h {
                    let row = y*w
                    for x in 0..<w { f[x] = dst[row + x] }
                    pass(w)
                    for x in 0..<w { dst[row + x] = dd[x] }
                }
            }}}}}
        }
        return d
    }

    /// Close with an exact disc: grow then shrink.
    static func close(_ solid: Mask, w: Int, h: Int, radius: Float) -> Mask {
        guard radius >= 0.5 else { return solid }
        let n = w*h
        let r2 = radius*radius + 0.5
        var grown = Mask(repeating: 0, count: n)
        let d1 = distance2(solid, w: w, h: h)
        d1.withUnsafeBufferPointer { src in
            grown.withUnsafeMutableBufferPointer { dst in
                for i in 0..<n { dst[i] = src[i] <= r2 ? 1 : 0 }
            }
        }
        var out = Mask(repeating: 0, count: n)
        let d2 = distance2(grown, w: w, h: h, invert: true)
        d2.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for i in 0..<n { dst[i] = src[i] > r2 ? 1 : 0 }
            }
        }
        return out
    }

    /// Close with a square brush — the hairline seal between neighbouring
    /// plates. Separable, so it costs a fraction of the disc version.
    static func closeBox(_ solid: Mask, w: Int, h: Int, side: Int) -> Mask {
        guard side >= 3, w > 0, h > 0 else { return solid }
        let r = side/2
        let n = w*h
        var a = Mask(repeating: 0, count: n)
        var b = Mask(repeating: 0, count: n)

        /// One separable pass. `dilate` picks max, otherwise min.
        func run(_ src: Mask, _ dst: inout Mask, _ dilate: Bool) {
            src.withUnsafeBufferPointer { s in
                b.withUnsafeMutableBufferPointer { mid in
                    for y in 0..<h {
                        let row = y*w
                        for x in 0..<w {
                            var acc: UInt8 = dilate ? 0 : 1
                            let lo = max(0, x - r), hi = min(w - 1, x + r)
                            if dilate {
                                for xx in lo...hi where s[row + xx] != 0 {
                                    acc = 1
                                    break
                                }
                            } else {
                                if lo > x - r || hi < x + r { acc = 0 }
                                if acc != 0 {
                                    for xx in lo...hi where s[row + xx] == 0 {
                                        acc = 0
                                        break
                                    }
                                }
                            }
                            mid[row + x] = acc
                        }
                    }
                }
            }
            b.withUnsafeBufferPointer { mid in
                dst.withUnsafeMutableBufferPointer { out in
                    for y in 0..<h {
                        let row = y*w
                        let lo = max(0, y - r), hi = min(h - 1, y + r)
                        for x in 0..<w {
                            var acc: UInt8 = dilate ? 0 : 1
                            if dilate {
                                for yy in lo...hi where mid[yy*w + x] != 0 {
                                    acc = 1
                                    break
                                }
                            } else {
                                if lo > y - r || hi < y + r { acc = 0 }
                                if acc != 0 {
                                    for yy in lo...hi where mid[yy*w + x] == 0 {
                                        acc = 0
                                        break
                                    }
                                }
                            }
                            out[row + x] = acc
                        }
                    }
                }
            }
        }
        run(solid, &a, true)
        var out = Mask(repeating: 0, count: n)
        run(a, &out, false)
        return out
    }
}
