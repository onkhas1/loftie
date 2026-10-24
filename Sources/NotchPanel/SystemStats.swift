import Foundation
import Darwin

/// Статусы системы: диск, корзина, сеть, процессор.
final class SystemStats: ObservableObject {
    enum Trash: Equatable { case unknown, noAccess, size(Int64) }

    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var trash: Trash = .unknown
    @Published var down: Double = 0
    @Published var up: Double = 0
    @Published var cpu: Double = 0

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var lastNet: (down: UInt64, up: UInt64, time: Date)?
    private var lastTicks: (busy: UInt64, total: UInt64)?

    init() {
        tick()
        refreshSlow()
        fastTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshSlow() }
    }

    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

    /// Сеть и процессор: часто и дёшево.
    private func tick() {
        let now = Date()
        if let net = Self.networkBytes() {
            if let last = lastNet, net.down >= last.down, net.up >= last.up {
                let dt = now.timeIntervalSince(last.time)
                if dt > 0 {
                    down = Double(net.down - last.down) / dt
                    up = Double(net.up - last.up) / dt
                }
            }
            lastNet = (net.down, net.up, now)
        }
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
    }

    /// Диск и корзина: редко, корзину считаем в фоне.
    func refreshSlow() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        }
        DispatchQueue.global(qos: .utility).async {
            let result = Self.trashSize()
            DispatchQueue.main.async { self.trash = result }
        }
    }

    private static func trashSize() -> Trash {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        // Без «Полного доступа к диску» macOS не пускает в корзину
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return .noAccess }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var total: Int64 = 0
        if let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let file as URL in items {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return .size(total)
    }

    private static func networkBytes() -> (down: UInt64, up: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var down: UInt64 = 0, up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = pointer {
            let name = String(cString: addr.pointee.ifa_name)
            if addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
               let data = addr.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(stats.ifi_ibytes)
                up += UInt64(stats.ifi_obytes)
            }
            pointer = addr.pointee.ifa_next
        }
        return (down, up)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }
}

/// Форматирование чисел по-русски.
enum Fmt {
    private static let long = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
    private static let short = ["B", "K", "M", "G", "T"]

    private static func scale(_ bytes: Double) -> (Double, Int) {
        var value = max(bytes, 0), unit = 0
        while value >= 1000, unit < 4 { value /= 1000; unit += 1 }
        return (value, unit)
    }

    private static func number(_ value: Double) -> String {
        let text = value < 10 && value > 0 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func bytes(_ bytes: Int64) -> String {
        let (value, unit) = scale(Double(bytes))
        return "\(number(value)) \(long[unit])"
    }

    /// Коротко для крыльев челки: «118G».
    static func shortBytes(_ bytes: Double) -> String {
        let (value, unit) = scale(bytes)
        return number(value).replacingOccurrences(of: ",", with: ".") + short[unit]
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scale(bytesPerSecond)
        return "\(number(value)) \(long[unit])/с"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
