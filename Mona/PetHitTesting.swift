//
//  PetHitTesting.swift
//  Mona
//

import AppKit
import SwiftUI

/// Layout numbers shared by the window, the SwiftUI hierarchy and the hit
/// tester, so the three cannot drift apart.
enum PetLayout {
    static let windowSize = CGSize(width: 720, height: 280)
    static let spriteSize = CGSize(width: 250, height: 230)
    static let dialogueSize = CGSize(width: 450, height: 154)
    static let dialogueBottomPadding: CGFloat = 28
    static let namePlateSize = CGSize(width: 156, height: 44)
    static let namePlateRotation = Angle.degrees(-5)
    static let namePlateOffset = CGSize(width: 36, height: 4)

    /// Coordinate space the interactive regions are reported in.
    static let rootSpace = "monaPetRoot"

    /// Rect that an `Image(...).scaledToFit()` of `imageSize` actually covers
    /// inside `frame`.
    static func aspectFitRect(for imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }

        let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: frame.midX - fittedSize.width / 2,
            y: frame.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

/// The Persona-style balloon is plain polygon geometry, so the rendered shape
/// and the clickable region can both be derived from one set of points.
///
/// All points use SwiftUI's orientation: origin top-left, y growing downwards.
enum DialogueBalloonGeometry {
    static func balloonPoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX + 58, y: rect.minY + 30),
            CGPoint(x: rect.maxX - 17, y: rect.minY + 12),
            CGPoint(x: rect.maxX - 8, y: rect.maxY - 12),
            CGPoint(x: rect.minX + 70, y: rect.maxY - 24),
            CGPoint(x: rect.minX + 30, y: rect.maxY - 53),
            CGPoint(x: rect.minX + 46, y: rect.maxY - 57),
            CGPoint(x: rect.minX + 5, y: rect.maxY - 89),
            CGPoint(x: rect.minX + 61, y: rect.maxY - 75)
        ]
    }

    static func namePlatePoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX + 7, y: rect.minY + 7),
            CGPoint(x: rect.maxX - 17, y: rect.minY + 2),
            CGPoint(x: rect.maxX - 4, y: rect.maxY - 8),
            CGPoint(x: rect.minX + 18, y: rect.maxY - 2)
        ]
    }

    static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    /// Where a click has to land for the dialogue box to react: the balloon
    /// body, the heavy black/white border stroked on top of it, and the tilted
    /// name plate that hangs outside the balloon.
    ///
    /// Kept as separate paths and tested one by one, which avoids both boolean
    /// path operations and fill-rule surprises where a stroke outline would
    /// punch a hole through the body.
    static func hitPaths(in rect: CGRect) -> [CGPath] {
        let balloon = path(through: balloonPoints(in: rect)).cgPath
        let plate = path(
            through: namePlatePoints(in: CGRect(origin: .zero, size: PetLayout.namePlateSize))
        )
        .applying(namePlateTransform(in: rect))
        .cgPath

        return [
            balloon,
            balloon.copy(
                strokingWithWidth: 13,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            ),
            plate,
            plate.copy(
                strokingWithWidth: 10,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
        ]
    }

    /// Mirrors `.frame(...).rotationEffect(...).offset(...)` as applied to the
    /// name plate inside a `ZStack(alignment: .topLeading)`.
    private static func namePlateTransform(in rect: CGRect) -> CGAffineTransform {
        let center = CGPoint(
            x: PetLayout.namePlateSize.width / 2,
            y: PetLayout.namePlateSize.height / 2
        )
        return CGAffineTransform.identity
            .translatedBy(
                x: rect.minX + PetLayout.namePlateOffset.width,
                y: rect.minY + PetLayout.namePlateOffset.height
            )
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: PetLayout.namePlateRotation.radians)
            .translatedBy(x: -center.x, y: -center.y)
    }
}

/// What `DesktopPetView` is drawing right now, published so the window can
/// decide whether the cursor sits on actual artwork or on empty space.
///
/// Frames are in the root view's SwiftUI coordinate space (origin top-left,
/// y growing downwards).
final class PetInteractionRegions {
    /// Invoked whenever a region changes, so the window can re-evaluate mouse
    /// passthrough even while the cursor is standing still.
    var didChange: (() -> Void)?

    private(set) var spriteFrame: CGRect = .zero
    private(set) var dialogueFrame: CGRect = .zero
    private(set) var isDialogueVisible = false
    private var spriteImageName: String?
    private var dialogueHitPaths: [CGPath] = []
    private var dialogueHitPathsSize: CGSize = .zero

    func setSpriteFrame(_ frame: CGRect) {
        guard frame != spriteFrame else { return }
        spriteFrame = frame
        didChange?()
    }

    func setDialogueFrame(_ frame: CGRect) {
        guard frame != dialogueFrame else { return }
        dialogueFrame = frame
        if frame.size != dialogueHitPathsSize {
            dialogueHitPathsSize = frame.size
            dialogueHitPaths = DialogueBalloonGeometry.hitPaths(
                in: CGRect(origin: .zero, size: frame.size)
            )
        }
        didChange?()
    }

    func setDialogueVisible(_ isVisible: Bool) {
        guard isVisible != isDialogueVisible else { return }
        isDialogueVisible = isVisible
        didChange?()
    }

    /// The frame currently on screen. Expressions change the silhouette —
    /// kirakira adds sparkles outside the body — so hit testing follows it.
    func setSpriteImageName(_ name: String?) {
        guard name != spriteImageName else { return }
        spriteImageName = name
        didChange?()
    }

    func containsInteractiveContent(at point: CGPoint) -> Bool {
        dialogueContainsInk(at: point) || containsPetInk(at: point)
    }

    /// Which band of the sprite a point falls in, or nil if it is not on the
    /// sprite at all.
    ///
    /// Bands are fractions of the frame rather than alpha tests on purpose: a
    /// hand stroking across his head passes over the gap between his ears, and
    /// that should not read as the hand having left.
    func touchZone(at point: CGPoint) -> PetTouchZone? {
        guard spriteFrame.height > 0, spriteFrame.contains(point) else { return nil }

        // The sprite frame and the dialogue box overlap by a strip 20pt wide
        // that spans both bands, so reaching for the box would otherwise read as
        // a hand on his head. Whatever is being spoken wins the overlap, the
        // same precedence `containsInteractiveContent` uses.
        if dialogueContainsInk(at: point) {
            return nil
        }

        let down = (point.y - spriteFrame.minY) / spriteFrame.height
        let across = (point.x - spriteFrame.minX) / spriteFrame.width

        // Checked before the belly: the two share their rows, and only the
        // horizontal position separates them.
        if PetTouchTuning.tailBand.contains(down),
           PetTouchTuning.tailColumns.contains(across) {
            return .tail
        }
        if PetTouchTuning.headBand.contains(down) {
            return .head
        }
        if PetTouchTuning.bellyBand.contains(down) {
            return .belly
        }
        if PetTouchTuning.feetBand.contains(down) {
            return .feet
        }
        return .neutral
    }

    /// Whether the point is on the dialogue box, as opposed to the transparent
    /// corners of its frame.
    func dialogueContainsInk(at point: CGPoint) -> Bool {
        guard isDialogueVisible, dialogueFrame.contains(point) else { return false }

        let local = CGPoint(x: point.x - dialogueFrame.minX, y: point.y - dialogueFrame.minY)
        return dialogueHitPaths.contains { $0.contains(local) }
    }

    /// Whether the point is on Mona himself, as opposed to the dialogue box or
    /// the empty space around him.
    func containsPetInk(at point: CGPoint) -> Bool {
        guard spriteFrame.contains(point) else { return false }
        guard let spriteImageName, let image = NSImage(named: spriteImageName) else {
            // `PersonaInspiredCat` is drawn instead; treat the frame as solid.
            return true
        }

        // `NSImage.hitTest` reads the bitmap rep's alpha channel directly, so no
        // snapshot of the view hierarchy is needed. It works in an unflipped
        // space, hence the local y mirror. The 3pt probe adds a little slack
        // around antialiased edges.
        let local = CGPoint(x: point.x - spriteFrame.minX, y: spriteFrame.maxY - point.y)
        return image.hitTest(
            CGRect(x: local.x - 1.5, y: local.y - 1.5, width: 3, height: 3),
            withDestinationRect: PetLayout.aspectFitRect(
                for: image.size,
                in: CGRect(origin: .zero, size: spriteFrame.size)
            ),
            context: nil,
            hints: nil,
            flipped: false
        )
    }
}
