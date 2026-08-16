//
//  DesktopPetAppDelegate.swift
//  Mona
//
//  Created by Codex on 2026/7/26.
//

import AppKit
import SwiftUI

final class DesktopPetAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusAnimator: StatusBarRunAnimator?
    private var hostingView: PetHostingView<DesktopPetView>?
    private var globalMouseMonitor: Any?
    private var lastEvaluatedScreenPoint: NSPoint?
    private var strokes = PetStrokeRecognizer()
    private var strokeSettleSequence = 0
    private var isShowingPetCursor = false
    private let regions = PetInteractionRegions()
    private let touch = PetTouchState()
    private let machine = MachineStatusMonitor()
    private var settingsWindow: NSWindow?
    private let calendar = CalendarHUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        PetPreferences.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        regions.didChange = { [weak self] in
            self?.refreshMousePassthrough(force: true)
        }
        PetDialogueBook.shared.load()
        machine.start()
        createPetWindow()
        createStatusItem()
        startMouseTracking()
        // Restored rather than defaulted: the calendar is a second window on the
        // desktop, so it comes back only if you left it up.
        if PetPreferences.calendarVisible {
            calendar.show()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarSettingsChanged),
            name: PetPreferences.calendarSettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(petSettingsChanged),
            name: PetPreferences.petSettingsChanged,
            object: nil
        )

        for name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appActivationChanged),
                name: name,
                object: nil
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusAnimator?.stop()
        machine.stop()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        globalMouseMonitor = nil
    }

    private func createPetWindow() {
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screenFrame.maxX - PetLayout.windowSize.width - 48,
            y: screenFrame.minY + 56
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: PetLayout.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        // Start out transparent to clicks: the window is mostly empty space, so
        // failing towards passthrough is always the safer default.
        window.ignoresMouseEvents = true

        let rootView = DesktopPetView(
            regions: regions,
            touch: touch,
            machine: machine,
            openSettings: { [weak self] in self?.openSettings() },
            toggleVisibility: { [weak self] in self?.togglePetVisibility() },
            quit: { NSApp.terminate(nil) }
        )
        let hostingView = PetHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.hitTestHandler = { [weak self] point in
            self?.regions.containsInteractiveContent(at: point) ?? false
        }
        hostingView.mouseDidMove = { [weak self] in
            self?.handleMouseMovement()
        }
        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(petWindowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )

        // Off unless you have turned him on before. He is a window sitting over
        // your work, so a fresh install should not hand him to you unasked —
        // and once you have chosen, that choice is what is restored.
        applyPetVisibility(PetPreferences.petVisible)
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button = item.button {
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Mona：奔跑速度随 CPU 使用率变化")

            let animator = StatusBarRunAnimator(button: button, machine: machine)
            animator.start()
            statusAnimator = animator

            if button.image == nil, let fallback = NSImage(named: "MonaStatusIcon") {
                fallback.isTemplate = true
                fallback.size = NSSize(width: 20, height: 20)
                button.image = fallback
            }
        }
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "显示/隐藏桌宠",
                action: #selector(togglePetVisibility),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "显示/隐藏日历",
                action: #selector(toggleCalendarVisibility),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "设置…",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
        )

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出 Mona",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )
        item.menu = menu

        statusItem = item
    }

    /// The two monitors are complementary. While the window accepts clicks its
    /// tracking area reports movement (`.activeAlways`, since Mona is usually
    /// not the frontmost app); while the window is transparent to clicks it sees
    /// no local events at all and the global monitor takes over.
    private func startMouseTracking() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.handleMouseMovement()
        }
    }

    private func handleMouseMovement() {
        trackStroke()
        refreshMousePassthrough()
    }

    private func trackStroke() {
        guard let window, let hostingView, window.isVisible else { return }

        // Stroking is hover-only. With a button held this is a window drag —
        // the same motion — and must not be read as a hand petting him.
        guard NSEvent.pressedMouseButtons == 0 else {
            endStroke()
            return
        }

        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else {
            endStroke()
            return
        }

        let petPoint = hostingView.petSpacePoint(
            fromWindow: window.convertPoint(fromScreen: screenPoint)
        )
        strokes.track(
            x: screenPoint.x,
            zone: regions.touchZone(at: petPoint),
            at: ProcessInfo.processInfo.systemUptime
        )
        publishStroke()
        scheduleStrokeSettle()
    }

    private func endStroke() {
        strokes.reset()
        publishStroke()
    }

    private func publishStroke() {
        if touch.strokedZone != strokes.zone {
            touch.strokedZone = strokes.zone
        }
        if touch.strokeLean != strokes.lean {
            touch.strokeLean = strokes.lean
        }
    }

    /// A hand that stops moving produces no further events, so re-check just past
    /// the lapse deadline and let the stroke expire.
    private func scheduleStrokeSettle() {
        strokeSettleSequence += 1
        let sequence = strokeSettleSequence
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetTouchTuning.strokeLapse + 0.05
        ) { [weak self] in
            guard let self, sequence == strokeSettleSequence else { return }
            strokes.settle(at: ProcessInfo.processInfo.systemUptime)
            publishStroke()
        }
    }

    private func refreshMousePassthrough(force: Bool = false) {
        guard let window, let hostingView, window.isVisible else { return }
        // Re-gating mid-drag would fight `isMovableByWindowBackground`, which
        // moves the window along with the cursor.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let screenPoint = NSEvent.mouseLocation
        guard force || screenPoint != lastEvaluatedScreenPoint else { return }
        lastEvaluatedScreenPoint = screenPoint

        // Cheap exit for the global monitor: while the cursor is anywhere else
        // on screen, handling a mouse-moved event costs one rect comparison.
        var isOverPet = false
        var shouldReceiveEvents = false
        if window.frame.contains(screenPoint) {
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let petPoint = hostingView.petSpacePoint(fromWindow: windowPoint)
            // Always ask `containsInteractiveContent` rather than composing the
            // regions again here: it is the one list of everything clickable, and
            // anything added to it has to reach this gate or it will be silently
            // clicked through instead.
            shouldReceiveEvents = regions.containsInteractiveContent(at: petPoint)
            isOverPet = shouldReceiveEvents && regions.containsPetInk(at: petPoint)
        }

        showPetCursor(isOverPet)

        if window.ignoresMouseEvents == shouldReceiveEvents {
            window.ignoresMouseEvents = !shouldReceiveEvents
        }
    }

    /// An open hand while the cursor is on Mona himself.
    ///
    /// macOS only lets the frontmost app set the cursor, and Mona is an
    /// accessory that usually is not it — measured, not assumed: the call is
    /// made and silently ignored while another app is in front, and takes effect
    /// on every attempt once Mona is. Stealing focus on hover to work around
    /// that would cost far more than a cursor is worth, so the hand simply
    /// appears while he is the app being dealt with — which is to say from the
    /// moment you first click him, for as long as you are playing with him.
    ///
    /// Keyed to being on his artwork rather than to a stroke being recognised: a
    /// stroke takes a couple of deliberate passes to latch, so tying the cursor
    /// to it meant the hand only showed up once you were already doing the thing
    /// it was supposed to advertise.
    ///
    /// Pushed and popped rather than set, which restores whatever the cursor was
    /// before instead of assuming it was the arrow.
    private func showPetCursor(_ isOverPet: Bool) {
        // No check for being frontmost: `NSApp.isActive` reads false even when
        // the app has plainly been given the cursor, so gating on it only ever
        // suppressed the hand in the case it would have worked. When the app
        // really does not own the cursor the system simply ignores this.
        if isOverPet {
            // Re-applied on every move rather than only on arriving: the app may
            // not have owned the cursor when the pointer got here, and there is
            // no notification for having since been handed it.
            //
            // Set rather than pushed. Moving on and off him quickly churned the
            // cursor stack hard enough to leave a third cursor behind that was
            // neither the hand nor the arrow.
            NSCursor.openHand.set()
            isShowingPetCursor = true
        } else if isShowingPetCursor {
            isShowingPetCursor = false
            NSCursor.arrow.set()
        }
    }

    /// Losing frontmost status silently takes the cursor away from us, so the
    /// hand has to be given up at the same moment rather than left dangling.
    @objc private func appActivationChanged() {
        refreshMousePassthrough(force: true)
    }


    @objc private func petWindowDidMove(_ notification: Notification) {
        refreshMousePassthrough(force: true)
    }

    @objc private func togglePetVisibility() {
        guard let window else { return }
        applyPetVisibility(!window.isVisible)
    }

    /// Follows the settings window, which only ever writes the preference.
    @objc private func petSettingsChanged() {
        applyPetVisibility(PetPreferences.petVisible)
    }

    /// The one place the pet window is shown or hidden, so the menu item, the
    /// settings toggle and the restored preference cannot disagree.
    private func applyPetVisibility(_ wanted: Bool) {
        guard let window else { return }
        if wanted {
            window.makeKeyAndOrderFront(nil)
            refreshMousePassthrough(force: true)
        } else {
            window.orderOut(nil)
            window.ignoresMouseEvents = true
            lastEvaluatedScreenPoint = nil
            endStroke()
            // Nothing left under the cursor to justify the hand.
            showPetCursor(false)
        }
        touch.isPetVisible = window.isVisible
        UserDefaults.standard.set(window.isVisible, forKey: PetPreferences.petVisibleKey)
    }

    /// Brings up the settings window, building it the first time.
    ///
    /// Owned here rather than left to SwiftUI's `Settings` scene: reaching that
    /// means sending `showSettingsWindow:` into the responder chain, and an
    /// accessory app with no menu bar and no key window may have nobody in that
    /// chain to answer it. A window we hold ourselves cannot fail quietly.
    @objc private func toggleCalendarVisibility() {
        calendar.toggle()
    }

    @objc private func calendarSettingsChanged() {
        calendar.settingsChanged()
    }

    @objc func openSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // An accessory app's activation is cooperative — the system may decline
        // to pull it in front of whatever you were using, which leaves the window
        // opened but buried. This asks for the front regardless of that.
        window.orderFrontRegardless()
        // Nothing should be holding the keyboard when this opens. Opening it
        // activates the app, and a text field that grabbed first responder would
        // quietly collect whatever you typed next — which is how a path setting
        // ends up holding a single stray character.
        window.makeFirstResponder(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        // A hosting *controller*, not a hosting view: the settings content grows
        // and shrinks as sections are switched on and off, and only the
        // controller reports that back to the window. With a plain hosting view
        // the window keeps its first size and clips whatever appears later.
        let window = NSWindow(contentViewController: NSHostingController(rootView: PetSettingsView()))
        window.styleMask = [.titled, .closable]
        window.title = "Mona 设置"
        // Closing must not deallocate it; the toggles live in UserDefaults, but a
        // released window would leave `settingsWindow` pointing at nothing.
        window.isReleasedWhenClosed = false
        // Centred once, at birth. Re-centring on every open would drag a window
        // you had deliberately moved back to the middle.
        window.center()
        return window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Hosting view that refuses events landing on transparent artwork, and that
/// reports hover movement so the window can flip `ignoresMouseEvents`.
private final class PetHostingView<Content: View>: NSHostingView<Content> {
    /// Receives points in `PetInteractionRegions`' space (origin top-left).
    var hitTestHandler: ((CGPoint) -> Bool)?
    var mouseDidMove: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override var isOpaque: Bool {
        false
    }

    /// Converts a window point into the SwiftUI-facing space that
    /// `PetInteractionRegions` reports its frames in.
    func petSpacePoint(fromWindow windowPoint: NSPoint) -> CGPoint {
        petSpacePoint(fromLocal: convert(windowPoint, from: nil))
    }

    private func petSpacePoint(fromLocal point: NSPoint) -> CGPoint {
        isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Only ever replace our own area; SwiftUI installs its own and removing
        // those would break hover handling inside the hierarchy.
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        guard hitTestHandler?(petSpacePoint(fromLocal: local)) == true else { return nil }
        return super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        mouseDidMove?()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        mouseDidMove?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        mouseDidMove?()
    }
}
