import Foundation
import CryptoKit

// MARK: - 枚举

enum InboundProtocol: String, CaseIterable, Identifiable {
    case vless
    case vmess
    case trojan
    case shadowsocks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .shadowsocks: return "SS"
        }
    }

    var fullTitle: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        }
    }

    var supportsTLS: Bool { self != .shadowsocks }

    /// 这个协议的客户端标识字段叫 id（vless/vmess）还是 password（trojan/ss）。
    var usesPassword: Bool { self == .trojan || self == .shadowsocks }
}

enum InboundSecurity: String, CaseIterable, Identifiable {
    case none
    case tls
    case reality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .tls: return "TLS"
        case .reality: return "Reality"
        }
    }

    var jsonValue: String { rawValue }
}

enum InboundNetwork: String, CaseIterable, Identifiable {
    case tcp
    case ws
    case grpc

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
}

// MARK: - 随机 / 编码

enum PanelRandom {
    static let alphanumerics = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static func string(_ length: Int) -> String {
        var out = ""
        for _ in 0..<length {
            let index = Int.random(in: 0..<alphanumerics.count)
            out.append(alphanumerics[index])
        }
        return out
    }

    static func uuid() -> String {
        UUID().uuidString.lowercased()
    }

    static func password(_ length: Int = 24) -> String {
        string(length)
    }

    static func hex(_ length: Int) -> String {
        let digits = Array("0123456789abcdef")
        var out = ""
        for _ in 0..<length {
            out.append(digits[Int.random(in: 0..<digits.count)])
        }
        return out
    }

    static func shortId() -> String { hex(8) }

    static func port() -> Int { Int.random(in: 10000...60000) }

    /// 邮箱里不能有空格和奇怪符号，统一成小写连字符。
    static func slug(_ text: String) -> String {
        var out = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "client" : String(trimmed.prefix(20))
    }

    /// base64url（去掉补位的 =），Reality 密钥就用这个格式。
    static func base64URL(_ data: Data) -> String {
        var text = data.base64EncodedString()
        text = text.replacingOccurrences(of: "+", with: "-")
        text = text.replacingOccurrences(of: "/", with: "_")
        text = text.replacingOccurrences(of: "=", with: "")
        return text
    }
}

/// Reality 需要的 x25519 密钥对，字段格式与 Xray 一致（base64url 原始字节）。
struct RealityKeyPair {
    var privateKey: String
    var publicKey: String

    static func generate() -> RealityKeyPair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return RealityKeyPair(
            privateKey: PanelRandom.base64URL(privateKey.rawRepresentation),
            publicKey: PanelRandom.base64URL(privateKey.publicKey.rawRepresentation)
        )
    }
}

// MARK: - 面板设置

/// `setting/all` 里和订阅、TLS 证书相关的那几项；缺的字段留空。
struct PanelSettingsInfo {
    var subEnable: Bool = false
    var subPort: Int = 2096
    var subPath: String = "/sub/"
    var subJsonPath: String = "/json/"
    var subURI: String = ""
    var webCertFile: String = ""
    var webKeyFile: String = ""

    init(raw: [String: Any]) {
        subEnable = InboundSummary.boolean(raw["subEnable"]) ?? false
        subPort = InboundSummary.integer(raw["subPort"]) ?? 2096

        let path = InboundSummary.string(raw["subPath"]) ?? "/sub/"
        subPath = path.isEmpty ? "/sub/" : path

        let jsonPath = InboundSummary.string(raw["subJsonPath"]) ?? "/json/"
        subJsonPath = jsonPath.isEmpty ? "/json/" : jsonPath

        subURI = InboundSummary.string(raw["subURI"]) ?? ""
        webCertFile = InboundSummary.string(raw["webCertFile"]) ?? ""
        webKeyFile = InboundSummary.string(raw["webKeyFile"]) ?? ""
    }

    var subscriptionReady: Bool { subEnable && !subURI.isEmpty }
}

// MARK: - 新建入站

enum InboundDraftError: LocalizedError {
    case badPort
    case badNumber(String)
    case missingCertificate

    var errorDescription: String? {
        switch self {
        case .badPort:
            return "端口要填 1–65535 之间的数字"
        case .badNumber(let field):
            return field + "不是有效数字"
        case .missingCertificate:
            return "选了 TLS 但没填证书路径，Xray 会因为找不到证书启动失败"
        }
    }
}

struct InboundDraft {
    var protocolType: InboundProtocol = .vless
    var remark: String = ""
    var port: String = ""
    var listen: String = ""
    var security: InboundSecurity = .none
    var network: InboundNetwork = .tcp
    var serverName: String = ""
    var realityDest: String = "www.microsoft.com:443"
    var certFile: String = ""
    var keyFile: String = ""
    var wsPath: String = "/"
    var wsHost: String = ""
    var grpcService: String = "grpc"
    var email: String = ""
    var totalGB: String = ""
    var expiryDays: String = ""
    var enable: Bool = true

    func resolvedPort() throws -> Int {
        let text = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return PanelRandom.port()
        }
        guard let value = Int(text), value > 0, value < 65536 else {
            throw InboundDraftError.badPort
        }
        return value
    }

    func resolvedRemarks() -> String {
        let text = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return protocolType.fullTitle + " 节点"
        }
        return text
    }

    private func totalBytes() throws -> Double {
        let text = totalGB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        guard let value = Double(text), value >= 0 else {
            throw InboundDraftError.badNumber("流量配额")
        }
        return value * 1024 * 1024 * 1024
    }

    private func expiryMillis() throws -> Double {
        let text = expiryDays.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        guard let days = Double(text), days >= 0 else {
            throw InboundDraftError.badNumber("到期天数")
        }
        if days == 0 { return 0 }
        return (Date().timeIntervalSince1970 + days * 86400) * 1000
    }

    /// 组装成 `inbounds/add` 需要的那份 JSON。
    func makePayload() throws -> [String: Any] {
        let port = try resolvedPort()
        let total = try totalBytes()
        let expiry = try expiryMillis()
        let title = resolvedRemarks()

        let clientEmail: String = {
            let typed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty { return typed }
            return PanelRandom.slug(title) + "-" + PanelRandom.string(4)
        }()
        let subId = PanelRandom.string(16)

        var settings: [String: Any] = [:]
        switch protocolType {
        case .vless:
            var client: [String: Any] = [
                "id": PanelRandom.uuid(),
                "email": clientEmail,
                "limitIp": 0,
                "totalGB": total,
                "expiryTime": expiry,
                "enable": true,
                "tgId": "",
                "subId": subId,
                "reset": 0
            ]
            client["flow"] = ""
            settings["clients"] = [client]
            settings["decryption"] = "none"
            settings["fallbacks"] = []
        case .vmess:
            let client: [String: Any] = [
                "id": PanelRandom.uuid(),
                "alterId": 0,
                "email": clientEmail,
                "limitIp": 0,
                "totalGB": total,
                "expiryTime": expiry,
                "enable": true,
                "tgId": "",
                "subId": subId,
                "reset": 0
            ]
            settings["clients"] = [client]
        case .trojan:
            let client: [String: Any] = [
                "password": PanelRandom.password(),
                "email": clientEmail,
                "limitIp": 0,
                "totalGB": total,
                "expiryTime": expiry,
                "enable": true,
                "tgId": "",
                "subId": subId,
                "reset": 0
            ]
            settings["clients"] = [client]
            settings["fallbacks"] = []
        case .shadowsocks:
            let password = PanelRandom.password(16)
            let method = "aes-256-gcm"
            let client: [String: Any] = [
                "password": password,
                "method": method,
                "email": clientEmail,
                "limitIp": 0,
                "totalGB": total,
                "expiryTime": expiry,
                "enable": true,
                "tgId": "",
                "subId": subId,
                "reset": 0
            ]
            settings["clients"] = [client]
            settings["method"] = method
            settings["password"] = password
            settings["network"] = "tcp,udp"
        }

        var stream: [String: Any] = [:]
        stream["network"] = network.rawValue

        let effectiveSecurity: InboundSecurity = protocolType.supportsTLS ? security : .none
        stream["security"] = effectiveSecurity.jsonValue

        switch effectiveSecurity {
        case .none:
            break
        case .tls:
            let cert = certFile.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = keyFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cert.isEmpty, !key.isEmpty else {
                throw InboundDraftError.missingCertificate
            }
            var tls: [String: Any] = [:]
            let sni = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sni.isEmpty { tls["serverName"] = sni }
            tls["alpn"] = ["h2", "http/1.1"]
            tls["certificates"] = [["certificateFile": cert, "keyFile": key]]
            stream["tlsSettings"] = tls
        case .reality:
            let keys = RealityKeyPair.generate()
            let dest = realityDest.trimmingCharacters(in: .whitespacesAndNewlines)
            let sni = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = !sni.isEmpty ? sni : hostPart(of: dest)
            var reality: [String: Any] = [
                "show": false,
                "xver": 0,
                "dest": dest.isEmpty ? "www.microsoft.com:443" : dest,
                "serverNames": [name],
                "privateKey": keys.privateKey,
                "shortIds": [PanelRandom.shortId()],
                "settings": [
                    "publicKey": keys.publicKey,
                    "fingerprint": "chrome",
                    "serverName": "",
                    "spiderX": "/"
                ]
            ]
            reality["serverName"] = name
            stream["realitySettings"] = reality
        }

        switch network {
        case .tcp:
            break
        case .ws:
            var ws: [String: Any] = ["path": wsPath.trimmingCharacters(in: .whitespacesAndNewlines)]
            let host = wsHost.trimmingCharacters(in: .whitespacesAndNewlines)
            ws["headers"] = host.isEmpty ? [:] : ["Host": host]
            stream["wsSettings"] = ws
        case .grpc:
            let service = grpcService.trimmingCharacters(in: .whitespacesAndNewlines)
            stream["grpcSettings"] = [
                "serviceName": service.isEmpty ? "grpc" : service,
                "multiMode": false
            ]
        }

        let sniffing: [String: Any] = [
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false,
            "routeOnly": false
        ]

        func jsonString(_ object: [String: Any]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
                  let text = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return text
        }

        return [
            "up": 0,
            "down": 0,
            "total": 0,
            "remark": title,
            "enable": enable,
            "expiryTime": 0,
            "listen": listen.trimmingCharacters(in: .whitespacesAndNewlines),
            "port": port,
            "protocol": protocolType.rawValue,
            "settings": jsonString(settings),
            "streamSettings": jsonString(stream),
            "sniffing": jsonString(sniffing),
            "allocate": jsonString(["strategy": "always", "refresh": 5, "concurrency": 3])
        ]
    }

    private func hostPart(of dest: String) -> String {
        let trimmed = dest.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = trimmed.lastIndex(of: ":") {
            return String(trimmed[trimmed.startIndex..<index])
        }
        return trimmed.isEmpty ? "www.microsoft.com" : trimmed
    }
}

// MARK: - 新建客户端

struct ClientDraft {
    var email: String = ""
    var totalGB: String = ""
    var expiryDays: String = ""
    var limitIp: String = ""
    var flow: String = ""
    var identifier: String = ""
    var enable: Bool = true

    func makeSettingsJSON(inbound: InboundSummary) throws -> String {
        let totalText = totalGB.trimmingCharacters(in: .whitespacesAndNewlines)
        var total: Double = 0
        if !totalText.isEmpty {
            guard let value = Double(totalText), value >= 0 else {
                throw InboundDraftError.badNumber("流量配额")
            }
            total = value * 1024 * 1024 * 1024
        }

        let daysText = expiryDays.trimmingCharacters(in: .whitespacesAndNewlines)
        var expiry: Double = 0
        if !daysText.isEmpty {
            guard let days = Double(daysText), days >= 0 else {
                throw InboundDraftError.badNumber("到期天数")
            }
            if days > 0 {
                expiry = (Date().timeIntervalSince1970 + days * 86400) * 1000
            }
        }

        let ipText = limitIp.trimmingCharacters(in: .whitespacesAndNewlines)
        var limit = 0
        if !ipText.isEmpty {
            guard let value = Int(ipText), value >= 0 else {
                throw InboundDraftError.badNumber("同时在线 IP")
            }
            limit = value
        }

        let typedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = typedEmail.isEmpty
            ? inbound.protocolName + "-" + PanelRandom.string(6)
            : typedEmail

        var client: [String: Any] = [
            "email": resolvedEmail,
            "limitIp": limit,
            "totalGB": total,
            "expiryTime": expiry,
            "enable": enable,
            "tgId": "",
            "subId": PanelRandom.string(16),
            "reset": 0
        ]

        switch inbound.protocolName {
        case "vless":
            let typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            client["id"] = typed.isEmpty ? PanelRandom.uuid() : typed
            client["flow"] = flow
        case "vmess":
            let typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            client["id"] = typed.isEmpty ? PanelRandom.uuid() : typed
            client["alterId"] = 0
        case "trojan":
            let typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            client["password"] = typed.isEmpty ? PanelRandom.password() : typed
        case "shadowsocks":
            let typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let method = inbound.clients.first?.method ?? "aes-256-gcm"
            client["password"] = typed.isEmpty ? PanelRandom.password(16) : typed
            client["method"] = method
        default:
            let typed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            client["id"] = typed.isEmpty ? PanelRandom.uuid() : typed
        }

        let settings: [String: Any] = ["clients": [client]]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: []),
              let text = String(data: data, encoding: .utf8) else {
            throw InboundDraftError.badNumber("客户端设置")
        }
        return text
    }
}

// MARK: - 订阅地址

extension ShareLinkBuilder {
    /// 面板设置里改了订阅端口 / 路径时，按设置拼；否则退回 /sub/<subId>。
    static func subscriptionURL(subId: String, settings: PanelSettingsInfo?, panelURL: URL?) -> String? {
        guard !subId.isEmpty, let panelURL = panelURL else { return nil }
        var components = URLComponents()
        components.scheme = panelURL.scheme
        components.host = panelURL.host

        if let settings = settings, settings.subEnable {
            components.port = settings.subPort
            let path = settings.subPath
            let lead = path.hasPrefix("/") ? path : "/" + path
            let tail = lead.hasSuffix("/") ? lead : lead + "/"
            components.path = tail + subId
            if !settings.subURI.isEmpty {
                components.host = settings.subURI
            }
            return components.url?.absoluteString
        }

        components.port = panelURL.port
        components.path = "/sub/" + subId
        return components.url?.absoluteString
    }
}

// MARK: - 节点（订阅页用）

struct ShareNode: Identifiable {
    var inbound: InboundSummary
    var client: ClientSummary
    var link: String?
    var subscription: String?

    var id: String { "\(inbound.id)-\(client.id)" }
}
