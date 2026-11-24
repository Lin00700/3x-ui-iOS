import Foundation

/// 依据入站与客户端信息拼出分享链接（vless / vmess / trojan / ss）。
/// 3x-ui 面板里每行客户端的分享链接就是这个格式，这里做一份离线版本，
/// 页面照常能用自己的按钮；概览里可以一键复制、生成二维码。
enum ShareLinkBuilder {
    static func link(for inbound: InboundSummary, client: ClientSummary, fallbackHost: String) -> String? {
        let host = hostFor(inbound: inbound, fallbackHost: fallbackHost)
        guard !host.isEmpty, inbound.port > 0 else { return nil }
        let name = client.email.isEmpty ? inbound.name : client.email
        let fragment = urlEncode(name)

        switch inbound.protocolName {
        case "vless":
            guard !client.identifier.isEmpty else { return nil }
            var params = baseParameters(inbound: inbound, host: host)
            if !client.flow.isEmpty {
                params.append("flow=\(urlEncode(client.flow))")
            }
            let query = params.isEmpty ? "" : "?" + params.joined(separator: "&")
            return "vless://\(client.identifier)@\(host):\(inbound.port)\(query)#\(fragment)"

        case "vmess":
            guard !client.identifier.isEmpty else { return nil }
            var object: [String: Any] = [
                "v": "2",
                "ps": name,
                "add": host,
                "port": String(inbound.port),
                "id": client.identifier,
                "aid": "0",
                "scy": "auto",
                "net": inbound.network,
                "type": "none",
                "host": streamHost(inbound: inbound),
                "path": streamPath(inbound: inbound),
                "tls": inbound.security == "tls" ? "tls" : "",
                "sni": inbound.tlsServerName ?? ""
            ]
            if inbound.security == "reality" {
                object["tls"] = "reality"
            }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return "vmess://" + Data(json.utf8).base64EncodedString()

        case "trojan":
            let password = client.identifier.isEmpty ? client.subId : client.identifier
            guard !password.isEmpty else { return nil }
            let params = securityParameters(inbound: inbound, host: host)
            let query = params.isEmpty ? "" : "?" + params.joined(separator: "&")
            return "trojan://\(urlEncode(password))@\(host):\(inbound.port)\(query)#\(fragment)"

        case "shadowsocks":
            let password = client.identifier.isEmpty ? client.subId : client.identifier
            guard !password.isEmpty else { return nil }
            let method = client.method.isEmpty ? "aes-256-gcm" : client.method
            let userInfo = "\(method):\(password)"
            let encoded = Data(userInfo.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            return "ss://\(encoded)@\(host):\(inbound.port)#\(fragment)"

        default:
            return nil
        }
    }

    /// 订阅地址：3x-ui 默认的 sub 路径是 /sub/<subId>，端口与主机沿用当前面板。
    /// 面板若在设置里改了订阅端口，这里拿不到，所以只作为便捷入口。
    static func subscriptionURL(for client: ClientSummary, panelURL: URL?) -> String? {
        guard !client.subId.isEmpty, let panelURL = panelURL else { return nil }
        var components = URLComponents()
        components.scheme = panelURL.scheme
        components.host = panelURL.host
        components.port = panelURL.port
        components.path = "/sub/\(client.subId)"
        return components.url?.absoluteString
    }

    // MARK: - 细节

    private static func hostFor(inbound: InboundSummary, fallbackHost: String) -> String {
        let listen = InboundSummary.string(inbound.raw["listen"]) ?? ""
        if !listen.isEmpty && listen != "0.0.0.0" && listen != "::" && listen != "::0" {
            return listen
        }
        return fallbackHost
    }

    private static func baseParameters(inbound: InboundSummary, host: String) -> [String] {
        var params = ["type=\(inbound.network)"]
        params.append(contentsOf: securityParameters(inbound: inbound, host: host))
        return params
    }

    private static func securityParameters(inbound: InboundSummary, host: String) -> [String] {
        var params: [String] = []
        switch inbound.security {
        case "tls":
            params.append("security=tls")
            if let sni = inbound.tlsServerName { params.append("sni=\(urlEncode(sni))") }
            if let alpn = alpn(inbound: inbound) { params.append("alpn=\(urlEncode(alpn))") }
        case "reality":
            let reality = InboundSummary.dictionary(inbound.stream["realitySettings"])
            params.append("security=reality")
            if let sni = inbound.tlsServerName { params.append("sni=\(urlEncode(sni))") }
            if let publicKey = InboundSummary.string(reality["publicKey"]), !publicKey.isEmpty {
                params.append("pbk=\(urlEncode(publicKey))")
            }
            if let shortId = InboundSummary.string(reality["shortId"]), !shortId.isEmpty {
                params.append("sid=\(urlEncode(shortId))")
            }
            if let settings = reality["settings"] as? [String: Any],
               let fingerprint = InboundSummary.string(settings["fingerprint"]), !fingerprint.isEmpty {
                params.append("fp=\(urlEncode(fingerprint))")
            } else {
                params.append("fp=chrome")
            }
        default:
            params.append("security=none")
        }

        switch inbound.network {
        case "ws", "httpupgrade":
            let ws = InboundSummary.dictionary(inbound.stream["wsSettings"])
            let wsAlt = InboundSummary.dictionary(inbound.stream["httpupgradeSettings"])
            let path = InboundSummary.string(ws["path"]) ?? InboundSummary.string(wsAlt["path"]) ?? ""
            if !path.isEmpty { params.append("path=\(urlEncode(path))") }
            let hostHeader = InboundSummary.string((ws["headers"] as? [String: Any])?["Host"])
                ?? InboundSummary.string((wsAlt["headers"] as? [String: Any])?["Host"])
                ?? ""
            if !hostHeader.isEmpty { params.append("host=\(urlEncode(hostHeader))") }
        case "grpc":
            let grpc = InboundSummary.dictionary(inbound.stream["grpcSettings"])
            if let serviceName = InboundSummary.string(grpc["serviceName"]), !serviceName.isEmpty {
                params.append("serviceName=\(urlEncode(serviceName))")
            }
            if InboundSummary.boolean(grpc["multiMode"]) == true {
                params.append("mode=multi")
            }
        case "xhttp", "splithttp":
            let xhttp = InboundSummary.dictionary(inbound.stream["xhttpSettings"])
            let path = InboundSummary.string(xhttp["path"]) ?? ""
            if !path.isEmpty { params.append("path=\(urlEncode(path))") }
            if let mode = InboundSummary.string(xhttp["mode"]), !mode.isEmpty {
                params.append("mode=\(urlEncode(mode))")
            }
        case "tcp":
            let tcp = InboundSummary.dictionary(inbound.stream["tcpSettings"])
            let header = InboundSummary.dictionary(tcp["header"])
            if let type = InboundSummary.string(header["type"]), type == "http" {
                params.append("headerType=http")
                if let request = header["request"] as? [String: Any],
                   let pathList = InboundSummary.dictionary(request["path"])["path"] as? [String],
                   let first = pathList.first, !first.isEmpty {
                    params.append("path=\(urlEncode(first))")
                }
            }
        default:
            break
        }
        return params
    }

    private static func streamHost(inbound: InboundSummary) -> String {
        let ws = InboundSummary.dictionary(inbound.stream["wsSettings"])
        return InboundSummary.string((ws["headers"] as? [String: Any])?["Host"]) ?? ""
    }

    private static func streamPath(inbound: InboundSummary) -> String {
        let ws = InboundSummary.dictionary(inbound.stream["wsSettings"])
        return InboundSummary.string(ws["path"]) ?? ""
    }

    private static func alpn(inbound: InboundSummary) -> String? {
        let tls = InboundSummary.dictionary(inbound.stream["tlsSettings"])
        if let list = tls["alpn"] as? [String], !list.isEmpty {
            return list.joined(separator: ",")
        }
        return nil
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
