import Foundation

/// 接口路径：`api` 相对 `/panel/api/`，`root` 相对面板根路径。
/// 3x-ui 各版本路径有出入，写操作按顺序兜底尝试。
enum PanelEndpoint {
    case api(String)
    case root(String)
}

/// 面板的写入接口：入站增删改、客户端管理、Xray 重启、日志与面板设置。
/// 与网页共用同一套 session（cookie），未登录时用已保存的账号密码重登一次。
extension PanelAPIClient {

    // MARK: - 入站

    func fetchInbounds(completion: @escaping (Result<[InboundSummary], PanelAPIError>) -> Void) {
        prepareSession { [weak self] problem in
            guard let self = self else { return }
            if let problem = problem {
                completion(.failure(problem))
                return
            }
            self.requestEnvelope(path: "inbounds/list") { result in
                switch result {
                case .success(let object):
                    let raw = (object as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
                    completion(.success(raw.compactMap { InboundSummary.parse($0) }))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func addInbound(payload: [String: Any], completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/add"),
            .root("panel/xui/API/inbounds/add")
        ], body: payload, completion: completion)
    }

    func updateInbound(id: Int, payload: [String: Any], completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/update/\(id)"),
            .root("panel/xui/API/inbounds/update/\(id)")
        ], body: payload, completion: completion)
    }

    func deleteInbound(id: Int, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/del/\(id)"),
            .root("panel/xui/API/inbounds/del/\(id)")
        ], body: nil, completion: completion)
    }

    /// 一次把入站的全部流量清零。
    func resetInboundTraffics(id: Int, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/resetAllClientTraffics/\(id)"),
            .api("inbounds/resetTraffic/\(id)"),
            .root("panel/xui/API/inbounds/resetAllClientTraffics/\(id)")
        ], body: nil, completion: completion)
    }

    // MARK: - 客户端

    /// `settingsJSON` 形如 `{"clients":[{...}]}`。
    func addClient(inboundId: Int, settingsJSON: String, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        let body: [String: Any] = ["id": inboundId, "settings": settingsJSON]
        send([
            .api("inbounds/addClient"),
            .root("panel/xui/API/inbounds/addClient")
        ], body: body, completion: completion)
    }

    func updateClient(inboundId: Int, clientId: String, settingsJSON: String, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        let body: [String: Any] = ["id": inboundId, "settings": settingsJSON]
        send([
            .api("inbounds/updateClient/\(clientId)"),
            .root("panel/xui/API/inbounds/updateClient/\(clientId)")
        ], body: body, completion: completion)
    }

    func deleteClient(inboundId: Int, clientId: String, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/\(inboundId)/delClient/\(clientId)"),
            .root("panel/xui/API/inbounds/\(inboundId)/delClient/\(clientId)")
        ], body: nil, completion: completion)
    }

    func resetClientTraffic(inboundId: Int, email: String, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/\(inboundId)/resetClientTraffic/\(email)"),
            .root("panel/xui/API/inbounds/\(inboundId)/resetClientTraffic/\(email)")
        ], body: nil, completion: completion)
    }

    func resetAllTraffics(completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("inbounds/resetAllTraffics"),
            .root("panel/xui/API/inbounds/resetAllTraffics")
        ], body: nil, completion: completion)
    }

    // MARK: - Xray / 面板

    func restartXray(completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("server/restartXrayService"),
            .root("server/restartXrayService"),
            .root("panel/xui/API/server/restartXrayService")
        ], body: nil, completion: completion)
    }

    func restartPanel(completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        send([
            .api("setting/restartPanel"),
            .root("panel/xui/API/setting/restartPanel")
        ], body: nil, completion: completion)
    }

    // MARK: - 日志

    func fetchLogs(xray: Bool, count: Int, completion: @escaping (Result<[String], PanelAPIError>) -> Void) {
        prepareSession { [weak self] problem in
            guard let self = self else { return }
            if let problem = problem {
                completion(.failure(problem))
                return
            }

            let leaf = xray ? "xraylogs" : "logs"
            self.requestEnvelope(path: "server/\(leaf)/\(count)", method: "POST", body: Data("{}".utf8)) { result in
                switch result {
                case .success(let object):
                    completion(.success(PanelAPIClient.logLines(from: object)))
                case .failure:
                    var url = self.rootURL
                    url.appendPathComponent("server")
                    url.appendPathComponent(leaf)
                    url.appendPathComponent("\(count)")
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                    request.httpBody = Data("{}".utf8)
                    self.perform(request) { second in
                        switch second {
                        case .success(let object):
                            completion(.success(PanelAPIClient.logLines(from: object)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    static func logLines(from object: Any?) -> [String] {
        if let text = object as? String {
            return text.split(separator: "\n").map(String.init)
        }
        if let list = object as? [Any] {
            var lines: [String] = []
            for item in list {
                if let text = item as? String {
                    lines.append(text)
                    continue
                }
                if let dict = item as? [String: Any] {
                    let time = InboundSummary.string(dict["datetime"]) ?? InboundSummary.string(dict["time"]) ?? ""
                    let message = InboundSummary.string(dict["message"]) ?? InboundSummary.string(dict["msg"]) ?? ""
                    if time.isEmpty {
                        lines.append(message)
                    } else {
                        lines.append(time + "  " + message)
                    }
                }
            }
            return lines
        }
        if let dict = object as? [String: Any] {
            var lines: [String] = []
            for key in dict.keys.sorted() {
                if let text = InboundSummary.string(dict[key]) {
                    lines.append(text)
                }
            }
            return lines
        }
        return []
    }

    // MARK: - 面板设置（订阅端口 / 证书路径）

    func fetchPanelSettings(completion: @escaping (Result<PanelSettingsInfo, PanelAPIError>) -> Void) {
        prepareSession { [weak self] problem in
            guard let self = self else { return }
            if let problem = problem {
                completion(.failure(problem))
                return
            }
            self.requestEnvelope(path: "setting/all") { result in
                switch result {
                case .success(let object):
                    completion(.success(PanelSettingsInfo(raw: InboundSummary.dictionary(object))))
                case .failure:
                    self.requestEnvelope(path: "setting/all", method: "POST", body: Data("{}".utf8)) { second in
                        switch second {
                        case .success(let object):
                            completion(.success(PanelSettingsInfo(raw: InboundSummary.dictionary(object))))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 发送

    func send(_ endpoints: [PanelEndpoint], body: [String: Any]?, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        prepareSession { [weak self] problem in
            guard let self = self else { return }
            if let problem = problem {
                completion(.failure(problem))
                return
            }
            var data = Data("{}".utf8)
            if let body = body, let encoded = try? JSONSerialization.data(withJSONObject: body, options: []) {
                data = encoded
            }
            self.sendEndpoints(endpoints, body: data, completion: completion)
        }
    }

    func sendEndpoints(_ endpoints: [PanelEndpoint], body: Data, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        guard let first = endpoints.first else {
            completion(.failure(.api("没有可用的接口路径")))
            return
        }
        let rest = Array(endpoints.dropFirst())

        let handle: (Result<Any, PanelAPIError>) -> Void = { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                if rest.isEmpty {
                    completion(.failure(error))
                } else if let self = self {
                    self.sendEndpoints(rest, body: body, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }

        switch first {
        case .api(let path):
            requestEnvelope(path: path, method: "POST", body: body, completion: handle)
        case .root(let path):
            var url = rootURL
            for component in path.split(separator: "/") where !component.isEmpty {
                url.appendPathComponent(String(component))
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            perform(request, completion: handle)
        }
    }
}
