//
//  CalendarHUDWindow.swift
//  Mona
//

import AppKit

/// Draws the rendered HUD and refuses clicks that land on transparent pixels.
///
/// Same rule as the pet window: the artwork is a tilted sticker inside a
/// rectangular window, so most of the frame is empty and anything landing there
/// belongs to whatever is underneath.
private final class CalendarHUDView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// Alpha-tested so the transparent corners stay click-through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let image, bounds.contains(convert(point, from: superview)) else { return nil }
        let local = convert(point, from: superview)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              bounds.width > 0, bounds.height > 0 else { return super.hitTest(point) }
        let x = Int(local.x / bounds.width * CGFloat(cg.width))
        // The bitmap runs top-down, the view bottom-up.
        let y = Int((1 - local.y / bounds.height) * CGFloat(cg.height))
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        return alpha(of: cg, x: x, y: y) > 16 ? self : nil
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 255 }
        let info = image.alphaInfo
        guard info == .premultipliedLast || info == .last else { return 255 }
        let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        guard offset + 3 < CFDataGetLength(data) else { return 255 }
        return bytes[offset + 3]
    }
}

/// The desktop calendar sticker: a borderless window you can drag anywhere.
@MainActor
final class CalendarHUDController {
    private var window: NSWindow?
    private var view: CalendarHUDView?
    private var content: CalendarHUDContent?
    private var tick: Timer?
    /// The weather icon's three drawings, already rendered. Cycling them is what
    /// makes the sun flicker and the rain fall; re-rendering the whole sticker
    /// two and a half times a second would not be worth it, and the three only
    /// differ inside the icon anyway.
    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var flip: Timer?
    /// Bumped on every refresh so a slow render that has been superseded can
    /// drop its result instead of putting yesterday back on the screen.
    private var renderJob = 0
    /// So a settings change can tell "the city moved" from "the width moved".
    private var lastCity = UserDefaults.standard.string(
        forKey: PetPreferences.calendarCityKey) ?? CalendarCity.defaultID

    let weather = CalendarWeatherSource()

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        resizeToPreference()
        weather.start()
        refresh(force: true)
        window.orderFrontRegardless()
        startTicking()
        UserDefaults.standard.set(true, forKey: PetPreferences.calendarVisibleKey)
    }

    func hide() {
        window?.orderOut(nil)
        tick?.invalidate()
        tick = nil
        // Nothing is on screen, so nothing should be animating it.
        flip?.invalidate()
        flip = nil
        weather.stop()
        UserDefaults.standard.set(false, forKey: PetPreferences.calendarVisibleKey)
    }

    /// Applies whatever the settings window just changed.
    ///
    /// Visibility is included because the settings toggle and the menu item are
    /// the same switch — both write the preference, and this is where it takes
    /// effect no matter which one was used.
    func settingsChanged() {
        // The city first: a new one invalidates the cached fix, and asking for
        // the weather again is worth doing even if the window is hidden — the
        // icon should already be right the next time it is shown.
        let city = UserDefaults.standard.string(forKey: PetPreferences.calendarCityKey)
            ?? CalendarCity.defaultID
        if city != lastCity {
            lastCity = city
            weather.locationChanged()
        }
        self.window?.level = Self.level(PetPreferences.calendarAlwaysOnTop)
        let wanted = PetPreferences.calendarVisible
        if wanted != isVisible {
            if wanted { show() } else { hide() }
            return
        }
        guard let window else { return }
        window.level = Self.level(PetPreferences.calendarAlwaysOnTop)
        resizeToPreference()
        refresh(force: true)
    }

    /// `.normal` rather than something below the desktop: turning the switch off
    /// means "stop hovering over my work", not "hide behind the wallpaper" —
    /// clicking another app should put it behind, and clicking the desktop
    /// should bring it back.
    private static func level(_ onTop: Bool) -> NSWindow.Level {
        onTop ? .floating : .normal
    }

    // MARK: - internals

    private func makeWindow() -> NSWindow {
        let width = preferredWidth
        let size = NSSize(width: width, height: width / CalendarHUDRenderer.aspect)
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = UserDefaults.standard.string(forKey: PetPreferences.calendarOriginKey)
        let origin = saved.flatMap { NSPointFromString($0) }
            ?? CGPoint(x: screen.maxX - size.width - 64, y: screen.maxY - size.height - 64)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = Self.level(PetPreferences.calendarAlwaysOnTop)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        let view = CalendarHUDView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        self.view = view

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { note in
            guard let moved = note.object as? NSWindow else { return }
            let point = moved.frame.origin
            MainActor.assumeIsolated {
                UserDefaults.standard.set(NSStringFromPoint(point),
                                          forKey: PetPreferences.calendarOriginKey)
            }
        }
        return window
    }

    private var preferredWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: PetPreferences.calendarWidthKey)
        return stored >= 160 ? CGFloat(stored) : 320
    }

    private func resizeToPreference() {
        guard let window, let view else { return }
        let width = preferredWidth
        let size = NSSize(width: width, height: width / CalendarHUDRenderer.aspect)
        guard size != window.frame.size else { return }
        // Anchored top-left, so growing the sticker does not walk it up the screen.
        let origin = CGPoint(x: window.frame.minX,
                             y: window.frame.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        view.frame = NSRect(origin: .zero, size: size)
    }

    /// Once a minute is enough for a date and a time-of-day card, and it lands
    /// the change within a minute of midnight without a wakeup budget.
    private func startTicking() {
        tick?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        timer.tolerance = 10
        tick = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh(force: Bool) {
        guard let window else { return }
        var next = CalendarHUDContent.now(weather: weather.kind)
        next.frame = 1
        guard force || next != content else { return }
        content = next
        let scale = window.screen?.backingScaleFactor ?? 2
        let width = window.frame.width
        // Off the main thread. Compositing five layers of a million pixels is
        // tens of milliseconds optimised and whole seconds in a debug build, and
        // on the main thread that is the app hanging — which is exactly what it
        // did. Nothing here touches AppKit until the images come back.
        renderJob += 1
        let job = renderJob
        DispatchQueue.global(qos: .userInitiated).async {
            let made = CalendarHUDRenderer.renderFrames(
                next, frames: [1, 2, 3], width: width, scale: scale)
            DispatchQueue.main.async { [weak self] in
                // A later refresh may have overtaken this one while it drew.
                guard let self, self.renderJob == job else { return }
                self.frames = made
                self.frameIndex = 0
                self.view?.image = made.first
                self.startFlipping()
            }
        }
    }

    /// The three drawings are meant to run 1-2-3 on a loop. They are drawn in
    /// register, so nothing but the icon moves between them.
    private func startFlipping() {
        flip?.invalidate()
        flip = nil
        guard frames.count > 1 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, self.frames.count > 1 else { return }
                self.frameIndex = (self.frameIndex + 1) % self.frames.count
                self.view?.image = self.frames[self.frameIndex]
            }
        }
        timer.tolerance = 0.1
        flip = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
