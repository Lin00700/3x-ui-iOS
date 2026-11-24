import Foundation

// MARK: - 概览

/// 3x-ui `/panel/api/server/status` + inbounds + onlines 聚合出来的快照。
struct PanelOverview {
    var cpuPercent: Double?
    var memUsed: Double?
    var memTotal: Double?
    var diskUsed: Double?
    var diskTotal: Double?
    var uptimeSeconds: Double?
    var xrayState: String
    var xrayVersion: String
    var onlineEmails: [String]
    var inbounds: [InboundSummary]
    var netUp: Double?
    var netDown: Double?
    var tcpCount: Double?
    var udpCount: Double?
    var publicIPv4: String
    var publicIPv6: String
    var fetchedAt: Date

    var onlineCount: Int { onlineEmails.count }

    var memPercent: Double? {
        guard let used = memUsed, let total = memTotal, total > 0 else { return nil }
        return min(max(used / total, 0), 1)
    }

    var diskPercent: Double? {
        guard let used = diskUsed, let total = diskTotal, total > 0 else { return nil }
        return min(max(used / total, 0), 1)
    }

    var isXrayRunning: Bool {
        xrayState.lowercased() == "running"
    }
}

// MARK: - 入站

struct InboundSummary: Identifiable {
    var id: Int
    var remark: String
    var protocolName: String
    var port: Int
    var enabled: Bool
    var up: Double
    var down: Double
    var total: Double
    var expiryTime: Double
    var clients: [ClientSummary]
    var raw: [String: Any]

    var name: String {
        remark.isEmpty ? "入站 #\(port)" : remark
    }

    var protocolLabel: String {
        protocolName.isEmpty ? "?" : protocolName.uppercased()
    }

    var traffic: Double { up + down }

    var trafficPercent: Double? {
        guard total > 0 else { return nil }
        return min(max(traffic / total, 0), 1)
    }

    var clientCount: Int { clients.count }

    var stream: [String: Any] { InboundSummary.dictionary(raw["streamSettings"]) }

    var network: String {
        let value = InboundSummary.string(stream["network"]) ?? "tcp"
        return value.isEmpty ? "tcp" : value
    }

    var security: String {
        let value = InboundSummary.string(stream["security"]) ?? "none"
        return value.isEmpty ? "none" : value
    }

    var tlsServerName: String? {
        let tls = InboundSummary.dictionary(stream["tlsSettings"])
        if let name = InboundSummary.string(tls["serverName"]), !name.isEmpty { return name }
        let reality = InboundSummary.dictionary(stream["realitySettings"])
        if let names = reality["serverNames"] as? [String], let first = names.first, !first.isEmpty { return first }
        if let name = InboundSummary.string(reality["serverName"]), !name.isEmpty { return name }
        if let host = InboundSummary.string(InboundSummary.dictionary(stream["wsSettings"])["host"]), !host.isEmpty { return host }
        return nil
    }

    // MARK: JSON 工具

    static func dictionary(_ value: Any?) -> [String: Any] {
        if let dict = value as? [String: Any] { return dict }
        if let text = value as? String,
           let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }

    static func array(_ value: Any?) -> [Any] {
        if let array = value as? [Any] { return array }
        if let text = value as? String,
           let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array
        }
        return []
    }

    static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let double = Double(text) { return double }
        return nil
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let int = Int(text) { return int }
        return nil
    }

    static func boolean(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            let lower = text.lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return nil
    }

    // MARK: 解析

    static func parse(_ raw: [String: Any]) -> InboundSummary? {
        guard let id = integer(raw["id"]) else { return nil }
        let settings = dictionary(raw["settings"])
        let stats = array(raw["clientStats"]).compactMap { $0 as? [String: Any] }
        let settingClients = array(settings["clients"]).compactMap { $0 as? [String: Any] }
        let clients = ClientSummary.merge(settingClients: settingClients, stats: stats)

        return InboundSummary(
            id: id,
            remark: string(raw["remark"]) ?? "",
            protocolName: (string(raw["protocol"]) ?? "").lowercased(),
            port: integer(raw["port"]) ?? 0,
            enabled: boolean(raw["enable"]) ?? true,
            up: number(raw["up"]) ?? 0,
            down: number(raw["down"]) ?? 0,
            total: number(raw["total"]) ?? 0,
            expiryTime: number(raw["expiryTime"]) ?? 0,
            clients: clients,
            raw: raw
        )
    }
}

// MARK: - 客户端

struct ClientSummary: Identifiable {
    var email: String
    var identifier: String       // vless/vmess 的 uuid，trojan/ss 的 password
    var subId: String
    var up: Double
    var down: Double
    var total: Double
    var expiryTime: Double
    var enabled: Bool
    var flow: String
    var method: String           // shadowsocks 加密方式

    var id: String { email.isEmpty ? identifier : email }

    var traffic: Double { up + down }

    var trafficPercent: Double? {
        guard total > 0 else { return nil }
        return min(max(traffic / total, 0), 1)
    }

    static func merge(settingClients: [[String: Any]], stats: [[String: Any]]) -> [ClientSummary] {
        var byEmail: [String: [String: Any]] = [:]
        for stat in stats {
            if let email = InboundSummary.string(stat["email"]) {
                byEmail[email] = stat
            }
        }

        var results: [ClientSummary] = []
        var seen = Set<String>()

        for client in settingClients {
            let email = InboundSummary.string(client["email"]) ?? ""
            let stat = byEmail[email] ?? [:]
            let identifier = InboundSummary.string(client["id"])
                ?? InboundSummary.string(client["password"])
                ?? ""
            let subId = InboundSummary.string(client["subId"])
                ?? InboundSummary.string(stat["subId"])
                ?? ""
            let summary = ClientSummary(
                email: email,
                identifier: identifier,
                subId: subId,
                up: InboundSummary.number(stat["up"]) ?? InboundSummary.number(client["up"]) ?? 0,
                down: InboundSummary.number(stat["down"]) ?? InboundSummary.number(client["down"]) ?? 0,
                total: InboundSummary.number(stat["total"]) ?? InboundSummary.number(client["total"]) ?? 0,
                expiryTime: InboundSummary.number(stat["expiryTime"]) ?? InboundSummary.number(client["expiryTime"]) ?? 0,
                enabled: InboundSummary.boolean(stat["enable"]) ?? InboundSummary.boolean(client["enable"]) ?? true,
                flow: InboundSummary.string(client["flow"]) ?? "",
                method: InboundSummary.string(client["method"]) ?? ""
            )
            results.append(summary)
            seen.insert(email)
        }

        // 只出现在 clientStats 里、settings 里没有的（例如旧版本）也列出来。
        for (email, stat) in byEmail where !seen.contains(email) {
            let summary = ClientSummary(
                email: email,
                identifier: "",
                subId: InboundSummary.string(stat["subId"]) ?? "",
                up: InboundSummary.number(stat["up"]) ?? 0,
                down: InboundSummary.number(stat["down"]) ?? 0,
                total: InboundSummary.number(stat["total"]) ?? 0,
                expiryTime: InboundSummary.number(stat["expiryTime"]) ?? 0,
                enabled: InboundSummary.boolean(stat["enable"]) ?? true,
                flow: "",
                method: ""
            )
            results.append(summary)
        }

        return results.sorted { $0.email < $1.email }
    }
}

// MARK: - 格式化

enum PanelFormat {
    static func bytes(_ value: Double?) -> String {
        guard let value = value, value > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = value
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 {
            return String(format: "%.0f %@", size, units[index])
        }
        return String(format: "%.2f %@", size, units[index])
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "—" }
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    static func percent(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    static func cpu(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func expiry(_ millis: Double?) -> String {
        guard let millis = millis, millis > 0 else { return "永久" }
        let date = Date(timeIntervalSince1970: millis / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
