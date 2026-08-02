//
//  MachineStatusReport.swift
//  Mona
//

import Foundation

/// Where "fine" stops and "you should do something about this" starts.
enum MachineStatusTuning {
    static let cpuBusy = 0.70
    static let memoryTight = 0.85
    static let storageFull = 0.85

    /// Only counts as low when nothing is charging it. Fifteen percent on the
    /// way up is not a problem worth being told about.
    static let batteryLow = 0.20
}

/// How the readings read out loud.
///
/// Memory is counted in binary units and storage in decimal ones. That is not an
/// inconsistency waiting to be tidied up — it is what macOS itself reports, and a
/// figure that disagrees with the system's own is worse than no figure at all.
enum MachineStatusFormat {
    static func percent(_ share: Double) -> String {
        String(format: "%.1f%%", share * 100)
    }

    static func memorySize(_ bytes: UInt64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    static func diskSize(_ bytes: UInt64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let perSecond = bytesPerSecond / 1024
        return perSecond >= 1024
            ? String(format: "%.1f MB/s", perSecond / 1024)
            : String(format: "%.1f KB/s", perSecond)
    }

    static func temperature(_ celsius: Double) -> String {
        String(format: "%.1f°C", celsius)
    }
}

/// Turns a reading into the pages Mona works through when asked how the machine
/// is doing.
enum MachineStatusReport {
    static func pages(
        for status: MachineStatus,
        book: PetDialogueBook = .shared
    ) -> [DialoguePage] {
        var pages: [DialoguePage] = []

        pages += lines(
            book,
            status.cpu.busy >= MachineStatusTuning.cpuBusy ? .statusCPUBusy : .statusCPU,
            [
                "cpu": MachineStatusFormat.percent(status.cpu.busy),
                "user": MachineStatusFormat.percent(status.cpu.user),
                "system": MachineStatusFormat.percent(status.cpu.system),
                "idle": MachineStatusFormat.percent(status.cpu.idle)
            ]
        )

        let memory = status.memory
        pages += lines(
            book,
            memory.usedShare >= MachineStatusTuning.memoryTight ? .statusMemoryTight : .statusMemory,
            [
                "memory": MachineStatusFormat.percent(memory.usedShare),
                "pressure": MachineStatusFormat.percent(memory.pressureShare),
                "app": MachineStatusFormat.memorySize(memory.app),
                "wired": MachineStatusFormat.memorySize(memory.wired),
                "compressed": MachineStatusFormat.memorySize(memory.compressed),
                "free": MachineStatusFormat.memorySize(memory.free),
                "total": MachineStatusFormat.memorySize(memory.total)
            ]
        )

        let storage = status.storage
        pages += lines(
            book,
            storage.usedShare >= MachineStatusTuning.storageFull ? .statusStorageFull : .statusStorage,
            [
                "storage": MachineStatusFormat.percent(storage.usedShare),
                "used": MachineStatusFormat.diskSize(storage.used),
                "free": MachineStatusFormat.diskSize(storage.available),
                "total": MachineStatusFormat.diskSize(storage.total)
            ]
        )

        // A machine with no battery simply has nothing to say on the subject.
        if let battery = status.battery {
            let isLow = !battery.isOnACPower && battery.charge <= MachineStatusTuning.batteryLow
            pages += lines(
                book,
                isLow ? .statusBatteryLow : .statusBattery,
                [
                    "battery": MachineStatusFormat.percent(battery.charge),
                    "source": battery.isOnACPower
                        ? (battery.isCharging ? "接着电源充电" : "接着电源")
                        : "用电池",
                    "health": battery.health.map(MachineStatusFormat.percent) ?? "未知",
                    "cycles": battery.cycleCount.map(String.init) ?? "未知",
                    "temperature": battery.temperature.map(MachineStatusFormat.temperature) ?? "未知"
                ]
            )
        }

        // Say what is actually known. A missing value filled in with "未知" reads
        // as a sentence nobody would utter — "网络走的是未连接" — so each level of
        // knowledge gets its own line instead.
        let network = status.network
        var networkValues = [
            "interface": network.interfaceName,
            "upload": MachineStatusFormat.rate(network.upload),
            "download": MachineStatusFormat.rate(network.download)
        ]
        if network.bsdName == nil {
            pages += lines(book, .statusNetworkOffline, [:])
        } else if let address = network.localAddress {
            networkValues["ip"] = address
            pages += lines(book, .statusNetwork, networkValues)
        } else {
            pages += lines(book, .statusNetworkNoAddress, networkValues)
        }

        return pages
    }

    /// One occasion contributes every line in its file, so a metric can be given
    /// more than one page just by adding to the file.
    private static func lines(
        _ book: PetDialogueBook,
        _ scenario: PetDialogueScenario,
        _ values: [String: String]
    ) -> [DialoguePage] {
        book.pages(for: scenario).filling(values)
    }
}
