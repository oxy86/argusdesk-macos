import Foundation

/// Parses NVIDIA's machine-readable inventory and optional per-process sample.
/// Missing utilization is shown as n/a: allocated VRAM does not imply GPU work.
struct NVIDIAMetrics {
    func parse(_ output: String) -> [Metric] {
        let lines = output.components(separatedBy: .newlines)
        var gpuIndices: [String: String] = [:]
        var metrics: [Metric] = []
        var processes: [String: (gpu: String, pid: String, name: String, memory: String, sm: String)] = [:]

        for line in lines where line.hasPrefix("gpu_csv=") {
            let fields = csv(String(line.dropFirst(8)))
            guard fields.count == 5 else { continue }
            gpuIndices[fields[1]] = fields[0]
            let utilization = Double(fields[2])
            let memoryPercent: Double?
            if let used = Double(fields[3]), let total = Double(fields[4]), total > 0 {
                memoryPercent = used / total * 100
            } else { memoryPercent = nil }
            metrics.append(Metric(label: "gpu\(fields[0])", value: "\(percent(fields[2])) · \(gigabytes(fields[3])) / \(gigabytes(fields[4]))", severity: utilization == nil && memoryPercent == nil ? .unknown : .ok,
                                  gpuUtilizationPercent: utilization, gpuMemoryUsagePercent: memoryPercent))
        }

        // Compute inventory supplies full process names and VRAM even on cards
        // whose driver cannot report per-process SM (compute) utilization.
        for line in lines where line.hasPrefix("gpu_process_csv=") {
            let fields = csv(String(line.dropFirst(16)))
            guard fields.count >= 4, let gpu = gpuIndices[fields[0]], Int(fields[1]) != nil else { continue }
            let name = fields[2..<(fields.count - 1)].joined(separator: ",")
            let key = "\(gpu):\(fields[1])"
            processes[key] = (gpu, fields[1], URL(fileURLWithPath: name).lastPathComponent, fields.last!, "n/a")
        }

        // Read the pmon header instead of assuming a fixed column order across
        // driver versions. Include graphics processes as well as model runners.
        var columns: [String] = []
        for line in lines where line.hasPrefix("gpu_pmon=") {
            let raw = String(line.dropFirst(9))
            let fields = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if fields.first == "#" {
                let header = Array(fields.dropFirst())
                if header.contains("pid"), header.contains("sm") { columns = header }
                continue
            }
            func field(_ name: String) -> String? {
                guard let index = columns.firstIndex(of: name), fields.indices.contains(index) else { return nil }
                return fields[index]
            }
            guard let gpu = field("gpu"), let pid = field("pid"), Int(pid) != nil else { continue }
            let key = "\(gpu):\(pid)"
            let prior = processes[key]
            processes[key] = (gpu, pid, prior?.name ?? field("command") ?? "unknown",
                              prior?.memory ?? field("fb") ?? "N/A", percent(field("sm") ?? "N/A"))
        }

        for process in processes.values.sorted(by: { ($0.gpu, Int($0.pid) ?? 0) < ($1.gpu, Int($1.pid) ?? 0) }) {
            metrics.append(Metric(label: "pid \(process.pid)", value: "\(process.name) · \(gigabytes(process.memory)) · SM \(process.sm) (gpu\(process.gpu))", severity: .ok))
        }
        if metrics.isEmpty { return [Metric(label: "gpu", value: "n/a", severity: .unknown)] }
        if processes.isEmpty {
            let inventoryAvailable = lines.contains("gpu_process_status=0")
            metrics.append(Metric(label: "gpu procs", value: inventoryAvailable ? "none" : "n/a", severity: .unknown))
        }
        return metrics
    }

    private func csv(_ line: String) -> [String] {
        line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func percent(_ raw: String) -> String {
        Double(raw).map { String(format: "%.0f%%", $0) } ?? "n/a"
    }

    private func gigabytes(_ raw: String) -> String {
        Double(raw).map { String(format: "%.2fGiB", $0 / 1024) } ?? "n/a"
    }
}
