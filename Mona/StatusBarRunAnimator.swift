import AppKit

/// Animates Mona's menu-bar silhouette at a pace driven by system CPU load.
final class StatusBarRunAnimator {
    private static let imageNames = (0..<8).map { "MonaRun\($0)" }

    /// Matches the approved preview at 50% CPU. Frames 3 and 7 linger at the
    /// two stride extremes while the in-between leg motion stays quick.
    private static let baseFrameDurations: [TimeInterval] = [
        0.060, 0.055, 0.055, 0.095,
        0.060, 0.055, 0.055, 0.095
    ]

    private weak var button: NSStatusBarButton?
    private let machine: MachineStatusMonitor
    private let frames: [NSImage]
    private var timer: Timer?
    private var frameIndex = 0
    private var smoothedCPU = 0.5

    init(button: NSStatusBarButton, machine: MachineStatusMonitor) {
        self.button = button
        self.machine = machine

        let images = Self.imageNames.compactMap { name -> NSImage? in
            guard let image = NSImage(named: name) else { return nil }
            image.isTemplate = true
            image.size = NSSize(width: 24, height: 20)
            return image
        }
        frames = images.count == Self.imageNames.count ? images : []
    }

    func start() {
        guard timer == nil, !frames.isEmpty else { return }
        frameIndex = 0
        button?.image = frames[frameIndex]
        scheduleNextFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextFrame() {
        guard button != nil else {
            stop()
            return
        }

        updateSmoothedCPU()
        let duration = Self.baseFrameDurations[frameIndex] / speedMultiplier
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advanceFrame() {
        timer = nil
        guard let button else { return }

        frameIndex = (frameIndex + 1) % frames.count
        button.image = frames[frameIndex]
        scheduleNextFrame()
    }

    private func updateSmoothedCPU() {
        let target = min(max(machine.latest?.cpu.busy ?? 0, 0), 1)
        smoothedCPU += (target - smoothedCPU) * 0.08
    }

    /// 50% CPU is exactly 1x. The caps keep the icon calm while idle and avoid
    /// turning the menu bar itself into meaningful CPU work under heavy load.
    ///
    /// Reversed, the same two caps swap ends — 1.55x idle down to 0.45x pinned —
    /// so the two readings agree at 50% and a flipped switch changes the
    /// direction of the response without changing how far it can go.
    private var speedMultiplier: Double {
        let load = PetPreferences.statusRunReversed ? 1 - smoothedCPU : smoothedCPU
        return 0.45 + (1.10 * load)
    }
}
