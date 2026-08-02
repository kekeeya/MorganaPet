//
//  MachineStatus.swift
//  Mona
//

import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

/// A reading of how the machine is doing.
///
/// Everything here is local and needs no permission. Nothing reads *what* you
/// are doing — only how hard the machine is working at it.
struct MachineStatus {
    var takenAt: Date
    var cpu: CPU
    var memory: Memory
    var storage: Storage
    /// Absent on a machine with no battery.
    var battery: Battery?
    var network: Network

    struct CPU {
        /// Shares of the last interval, each 0...1.
        var user: Double
        var system: Double
        var idle: Double

        var busy: Double { user + system }
    }

    struct Memory {
        var total: UInt64
        /// What the apps themselves are holding.
        var app: UInt64
        /// Pages the kernel cannot page out.
        var wired: UInt64
        var compressed: UInt64

        var used: UInt64 { app + wired + compressed }
        var usedShare: Double { share(of: used) }
        /// What is not currently spoken for.
        var free: UInt64 { total > used ? total - used : 0 }

        /// How squeezed the machine is, as opposed to how full it is. Wired and
        /// compressed pages are the ones it cannot simply let go of, so this
        /// climbs when memory is genuinely short rather than merely in use.
        var pressureShare: Double { share(of: wired + compressed) }

        private func share(of bytes: UInt64) -> Double {
            total == 0 ? 0 : Double(bytes) / Double(total)
        }
    }

    struct Storage {
        var total: UInt64
        var available: UInt64

        var used: UInt64 { total > available ? total - available : 0 }
        var usedShare: Double { total == 0 ? 0 : Double(used) / Double(total) }
    }

    struct Battery {
        /// 0...1.
        var charge: Double
        var isOnACPower: Bool
        var isCharging: Bool
        /// Capacity left relative to when it was new, 0...1.
        var health: Double?
        var cycleCount: Int?
        /// Degrees Celsius.
        var temperature: Double?
    }

    struct Network {
        /// As the system names it: "Wi-Fi", "Ethernet"…
        var interfaceName: String
        var bsdName: String?
        var localAddress: String?
        /// Bytes per second over the last interval.
        var upload: Double
        var download: Double
    }
}

/// Reads the machine's vital signs.
///
/// CPU load and network throughput are rates, so they mean nothing until there
/// are two samples to compare: the first reading reports them as zero and
/// everything else normally.
final class MachineStatusReader {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64)?
    /// Held at the width the kernel reports them, which is 32 bits: subtracting
    /// in that width is what makes the wrap at 4GB come out as a small delta
    /// instead of a number the size of the counter itself.
    private var previousTraffic: (sent: UInt32, received: UInt32, at: Date)?

    /// Asking the volume for its capacity costs about 8ms, and asking the system
    /// what "en0" is called costs another 4 — between them, nearly all the time a
    /// reading takes. Neither answer changes on the timescale anything here cares
    /// about, so both are kept rather than asked for again.
    private var cachedStorage: (value: MachineStatus.Storage, at: Date)?
    private var cachedInterfaceNames: [String: String] = [:]

    private static let storageFreshFor: TimeInterval = 60

    func read(at now: Date = Date()) -> MachineStatus {
        MachineStatus(
            takenAt: now,
            cpu: readCPU(),
            memory: readMemory(),
            storage: readStorage(at: now),
            battery: readBattery(),
            network: readNetwork(at: now)
        )
    }

    // MARK: - CPU

    private func readCPU() -> MachineStatus.CPU {
        guard let ticks = Self.cpuTicks() else {
            return MachineStatus.CPU(user: 0, system: 0, idle: 1)
        }
        defer { previousCPUTicks = ticks }

        guard let previous = previousCPUTicks else {
            return MachineStatus.CPU(user: 0, system: 0, idle: 1)
        }

        // Counters only ever climb, but guard anyway: a wrap would otherwise
        // underflow into an enormous share.
        let user = ticks.user >= previous.user ? ticks.user - previous.user : 0
        let system = ticks.system >= previous.system ? ticks.system - previous.system : 0
        let idle = ticks.idle >= previous.idle ? ticks.idle - previous.idle : 0
        let total = user + system + idle
        guard total > 0 else {
            return MachineStatus.CPU(user: 0, system: 0, idle: 1)
        }

        return MachineStatus.CPU(
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            idle: Double(idle) / Double(total)
        )
    }

    /// Nice time is folded into user, the way the system's own tools report it.
    private static func cpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return (
            user: UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.3),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2)
        )
    }

    // MARK: - Memory

    private func readMemory() -> MachineStatus.Memory {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MachineStatus.Memory(total: total, app: 0, wired: 0, compressed: 0)
        }

        let page = UInt64(vm_kernel_page_size)
        // Anonymous pages less the ones that can be thrown away on demand: the
        // same split Activity Monitor labels "App Memory".
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0

        return MachineStatus.Memory(
            total: total,
            app: app * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page
        )
    }

    // MARK: - Storage

    private func readStorage(at now: Date) -> MachineStatus.Storage {
        if let cached = cachedStorage,
           now.timeIntervalSince(cached.at) < Self.storageFreshFor {
            return cached.value
        }

        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        // "Important usage" is the figure Finder shows: what you could actually
        // free up, purgeable space included.
        let storage = MachineStatus.Storage(
            total: UInt64(values?.volumeTotalCapacity ?? 0),
            available: UInt64(max(values?.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        )
        cachedStorage = (storage, now)
        return storage
    }

    // MARK: - Battery

    private func readBattery() -> MachineStatus.Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?
                  .takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int,
              max > 0
        else {
            return nil
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        let smart = Self.smartBatteryProperties()

        var health: Double?
        if let design = smart?["DesignCapacity"] as? Int, design > 0,
           let now = (smart?["AppleRawMaxCapacity"] as? Int) ?? (smart?["MaxCapacity"] as? Int) {
            health = Double(now) / Double(design)
        }

        var temperature: Double?
        if let raw = smart?["Temperature"] as? Int {
            // Reported in hundredths of a degree Celsius.
            temperature = Double(raw) / 100
        }

        return MachineStatus.Battery(
            charge: Double(current) / Double(max),
            isOnACPower: state == kIOPSACPowerValue,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            health: health,
            cycleCount: smart?["CycleCount"] as? Int,
            temperature: temperature
        )
    }

    /// Cycle count, health and temperature are not in the power-source summary;
    /// they come from the battery's own IORegistry entry.
    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
                == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    // MARK: - Network

    private func readNetwork(at now: Date) -> MachineStatus.Network {
        let bsdName = Self.primaryInterface()
        let traffic = Self.traffic(on: bsdName)

        var upload = 0.0
        var download = 0.0
        if let traffic, let previous = previousTraffic {
            let seconds = now.timeIntervalSince(previous.at)
            if seconds > 0 {
                upload = Double(traffic.sent &- previous.sent) / seconds
                download = Double(traffic.received &- previous.received) / seconds
            }
        }
        if let traffic {
            previousTraffic = (traffic.sent, traffic.received, now)
        }

        // No display name is a naming failure, not an outage — fall back to the
        // BSD name. Being offline is `bsdName` itself coming back empty, and that
        // is answered with a different line rather than a word stuffed into this one.
        return MachineStatus.Network(
            interfaceName: bsdName.flatMap(displayName) ?? bsdName ?? "",
            bsdName: bsdName,
            localAddress: bsdName.flatMap(Self.address),
            upload: upload,
            download: download
        )
    }

    /// Whichever interface currently carries the default route.
    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Mona" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(
                  store, "State:/Network/Global/IPv4" as CFString
              ) as? [String: Any]
        else {
            return nil
        }
        return global["PrimaryInterface"] as? String
    }

    /// The name the system would show, "en0" being no use to anyone.
    private func displayName(for bsdName: String) -> String? {
        if let cached = cachedInterfaceNames[bsdName] { return cached }
        let name = Self.lookUpDisplayName(for: bsdName)
        if let name { cachedInterfaceNames[bsdName] = name }
        return name
    }

    private static func lookUpDisplayName(for bsdName: String) -> String? {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in all
        where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
            return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
        }
        return nil
    }

    private static func address(for bsdName: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: pointer.pointee.ifa_name) == bsdName,
                  let sockaddr = pointer.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                sockaddr, socklen_t(sockaddr.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else {
                continue
            }
            return String(cString: host)
        }
        return nil
    }

    private static func traffic(on bsdName: String?) -> (sent: UInt32, received: UInt32)? {
        guard let bsdName else { return nil }

        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: pointer.pointee.ifa_name) == bsdName,
                  let sockaddr = pointer.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_LINK),
                  let data = pointer.pointee.ifa_data
            else {
                continue
            }
            let link = data.assumingMemoryBound(to: if_data.self).pointee
            return (sent: link.ifi_obytes, received: link.ifi_ibytes)
        }
        return nil
    }
}

/// Keeps a recent reading to hand.
///
/// CPU load and throughput are differences between samples, so a reading taken
/// cold is blank on both. Sampling on a slow tick means the answer is ready the
/// moment it is asked for, without the pet having to stall while it takes two.
final class MachineStatusMonitor {
    /// Slow on purpose. These are slow-moving numbers, and a pet that reports
    /// how busy the machine is has no business being part of the reason.
    static let interval: TimeInterval = 5

    private(set) var latest: MachineStatus?
    private let reader = MachineStatusReader()
    private var timer: Timer?

    func start() {
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A fresh reading, taking one on the spot if none has been made yet.
    func current() -> MachineStatus {
        if let latest { return latest }
        sample()
        return latest ?? reader.read()
    }

    private func sample() {
        latest = reader.read()
    }
}
