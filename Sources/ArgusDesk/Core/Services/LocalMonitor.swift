import Darwin
import Foundation
import IOKit.ps

/// Reads local Mac status for the main window.
///
/// This service is self-contained and read-only. It uses native macOS and
/// Darwin APIs so the app does not need third-party monitoring libraries or
/// shell commands for local status.
final class LocalMonitor {
    /// Previous CPU tick sample used to calculate usage between refreshes.
    private var previousCPUTicks: CPUTicks?

    /// Returns the current local Mac status as UI-ready strings.
    ///
    /// Formatting happens here because the Window displays compact text values.
    func snapshot(label: String? = nil) -> LocalStatus {
        let friendly = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LocalStatus(
            hostname: friendly.isEmpty ? hostname() : friendly,
            osVersion: osVersion(),
            uptime: uptime(),
            battery: battery(),
            cpu: cpuUsage(),
            memory: memoryUsage(),
            disk: diskUsage(),
            network: network(),
            swap: swapUsage()
        )
    }

    /// Short local host name, with a stable fallback for unusual environments.
    private func hostname() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// Compact macOS version label.
    private func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Human-readable uptime from the current process info clock.
    private func uptime() -> String {
        formatDuration(ProcessInfo.processInfo.systemUptime)
    }

    /// Battery percentage or a useful desktop status.
    private func battery() -> String {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return "n/a"
        }

        guard
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let max = description[kIOPSMaxCapacityKey] as? Int,
            max > 0
        else {
            return "n/a"
        }

        let percent = Int(round((Double(current) / Double(max)) * 100))
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        return charging ? "\(percent)% chg" : "\(percent)%"
    }

    /// CPU usage calculated from host CPU tick deltas.
    ///
    /// The first sample has no previous value to compare against, so it reports
    /// `warming` until the next refresh interval provides a real percentage.
    private func cpuUsage() -> String {
        guard let currentTicks = readCPUTicks() else {
            return "n/a"
        }

        defer {
            previousCPUTicks = currentTicks
        }

        guard let previousTicks = previousCPUTicks else {
            return "warming"
        }

        let user = currentTicks.user - previousTicks.user
        let system = currentTicks.system - previousTicks.system
        let nice = currentTicks.nice - previousTicks.nice
        let idle = currentTicks.idle - previousTicks.idle
        let total = user + system + nice + idle

        guard total > 0 else {
            return "n/a"
        }

        let used = user + system + nice
        let percent = (Double(used) / Double(total)) * 100
        return "\(Int(round(percent)))%"
    }

    /// Memory usage from VM statistics.
    private func memoryUsage() -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return "n/a"
        }

        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return "n/a"
        }

        let pageSize = UInt64(hostPageSize)
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = used + free

        guard total > 0 else {
            return "n/a"
        }

        return "\(Int(round((Double(used) / Double(total)) * 100)))%"
    }

    /// Allocated swap from Darwin, in binary gigabytes. A machine with no
    /// allocated swap correctly reports zero rather than an unavailable value.
    private func swapUsage() -> String {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return "n/a" }
        return String(format: "%.2f GiB", Double(usage.xsu_used) / 1_073_741_824)
    }

    /// Root filesystem usage percentage.
    private func diskUsage() -> String {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            guard
                let total = attributes[.systemSize] as? NSNumber,
                let free = attributes[.systemFreeSize] as? NSNumber,
                total.uint64Value > 0
            else {
                return "n/a"
            }

            let used = total.uint64Value - free.uint64Value
            return "\(Int(round((Double(used) / Double(total.uint64Value)) * 100)))%"
        } catch {
            return "n/a"
        }
    }

    /// First active non-loopback IPv4 interface.
    private func network() -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return "n/a"
        }

        defer {
            freeifaddrs(interfaces)
        }

        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            defer {
                current = interface.pointee.ifa_next
            }

            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            guard
                isUp,
                !isLoopback,
                let address = interface.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let addressText = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return "\(name) \(String(decoding: addressText, as: UTF8.self))"
        }

        return "offline"
    }

    /// Reads aggregate CPU ticks for all processors.
    private func readCPUTicks() -> CPUTicks? {
        var cpuInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        var ticks = CPUTicks(user: 0, system: 0, nice: 0, idle: 0)
        let stride = Int(CPU_STATE_MAX)

        for processorIndex in 0..<Int(processorCount) {
            let offset = processorIndex * stride
            ticks.user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            ticks.system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            ticks.nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            ticks.idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }

        return ticks
    }

    /// Formats seconds into compact days/hours/minutes.
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(String(format: "%02dh", hours))"
        }

        if hours > 0 {
            return "\(hours)h \(String(format: "%02dm", minutes))"
        }

        return "\(minutes)m"
    }
}

/// Aggregate CPU tick counters used to calculate a refresh-to-refresh delta.
private struct CPUTicks {
    /// User-mode CPU ticks.
    var user: UInt64

    /// Kernel/system CPU ticks.
    var system: UInt64

    /// Nice-priority CPU ticks.
    var nice: UInt64

    /// Idle CPU ticks.
    var idle: UInt64
}
