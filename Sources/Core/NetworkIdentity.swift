import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// 读取当前网络身份：Wi-Fi 接口的 IPv4、MAC。
///
/// iOS 从 7.0 起屏蔽了 `getifaddrs` 返回的链路层地址（永远是 `02:00:00:00:00:00`），
/// 因此这里拿不到真实 MAC 就返回空串 —— 认证时改由用户填写的伪装 MAC 或
/// 服务端 `queryAuthState` 返回的 MAC 顶上。
enum NetworkIdentity {

    struct Info {
        var interfaceName: String
        var ipv4: String
        var mac: String
    }

    static let invalidMacs: Set<String> = ["00:00:00:00:00:00", "02:00:00:00:00:00"]

    // MARK: - 主入口

    /// 当前 Wi-Fi 接口身份；Wi-Fi 未连接或无 IPv4 时返回 nil。
    static func current() -> Info? {
        var candidates = interfaces()
        // en0 是 iPhone 的 Wi-Fi 接口；优先它，其余接口作为兜底（模拟器 / 特殊环境）
        candidates.sort { lhs, rhs in
            if lhs.interfaceName == "en0" { return true }
            if rhs.interfaceName == "en0" { return false }
            return lhs.interfaceName < rhs.interfaceName
        }
        return candidates.first
    }

    /// 本机所有可用 IPv4 接口。
    static func interfaces() -> [Info] {
        var result: [Info] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = entry.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(addr.pointee.sa_len)
            guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ipv4 = String(cString: host)
            guard isUsableIPv4(ipv4) else { continue }

            result.append(Info(interfaceName: name, ipv4: ipv4, mac: readMac(entry.pointee)))
        }
        return result
    }

    // MARK: - MAC

    private static func readMac(_ entry: ifaddrs) -> String {
        guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { return "" }
        let link = UnsafeMutableRawPointer(addr).assumingMemoryBound(to: sockaddr_dl.self)

        let nameLength = Int(link.pointee.sdl_nlen)
        let addressLength = Int(link.pointee.sdl_alen)
        guard addressLength == 6,
              let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) else {
            return ""
        }

        let base = UnsafeRawPointer(link).advanced(by: dataOffset + nameLength)
        let mac = (0..<6)
            .map { String(format: "%02X", base.load(fromByteOffset: $0, as: UInt8.self)) }
            .joined(separator: ":")
        return isUsableMac(mac) ? mac : ""
    }

    // MARK: - 校验 / 规范化

    static func normalizeMac(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let compact = trimmed.filter { $0.isHexDigit }
        guard compact.count == 12 else { return "" }
        var pairs: [String] = []
        var index = compact.startIndex
        for _ in 0..<6 {
            let next = compact.index(index, offsetBy: 2)
            pairs.append(String(compact[index..<next]).uppercased())
            index = next
        }
        return pairs.joined(separator: ":")
    }

    static func isUsableMac(_ value: String) -> Bool {
        let normalized = normalizeMac(value)
        guard !normalized.isEmpty else { return false }
        return !invalidMacs.contains(normalized)
    }

    static func isUsableIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
        let text = numbers.map(String.init).joined(separator: ".")
        guard text != "0.0.0.0", !text.hasPrefix("127."), !text.hasPrefix("169.254.") else { return false }
        return true
    }
}
