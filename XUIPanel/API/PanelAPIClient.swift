import Foundation
import WebKit

enum PanelAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case http(Int)
    case network(String)
    case decoding(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效，无法定位面板 API"
        case .unauthorized:
            return "面板未登录或账号密码不正确"
        case .http(let code):
            return "服务器返回 HTTP \(code)"
        case .network(let message):
            return message
        case .decoding(let message):
            return "返回数据无法解析（\(message)）"
        case .api(let message):
            return message
        }
    }
}

/// 直接对 3x-ui 的面板 API 说话（与网页同一套 session），
/// 给「快捷概览」提供状态、入站、在线数与数据库备份。
final class PanelAPIClient: NSObject {
    let rootURL: URL
    let apiBaseURL: URL

    private let username: String
    private let password: String
    /// 面板开了两步验证时填的验证码；没开就留空。
    private let twoFactorCode: String
    private let trustSelfSigned: Bool
    private var didAttemptLogin = false
    private var loginError: PanelAPIError?

    // MARK: - CSRF

    /// 3x-ui v3+ 的 POST /login 和所有写接口都由 CSRFMiddleware 保护：
    /// 先 GET {base}/csrf-token 把令牌写进 session，再带 X-CSRF-Token 回来，否则 403。
    /// v2.x 没有这个路由，取不到令牌就按老版本继续请求（v2 不校验 CSRF）。
    private let csrfLock = NSLock()
    private var storedCSRFToken: String?
    private let csrfQueue = DispatchQueue(label: "app.xui.csrf-token")
    private var csrfWaiters: [(String?) -> Void] = []
    private var csrfFetching = false

    private var csrfToken: String? {
        get {
            csrfLock.lock()
            defer { csrfLock.unlock() }
            return storedCSRFToken
        }
        set {
            csrfLock.lock()
            storedCSRFToken = newValue
            csrfLock.unlock()
        }
    }

    private static func isSafeMethod(_ method: String) -> Bool {
        switch method.uppercased() {
        case "GET", "HEAD", "OPTIONS", "TRACE":
            return true
        default:
            return false
        }
    }

    private var session: URLSession {
        if let existing = cachedSession { return existing }
        let created = makeSession()
        cachedSession = created
        return created
    }

    private var cachedSession: URLSession?

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    // MARK: - 路径推导

    /// 3x-ui 支持自定义 webBasePath，这里从用户填的面板地址里把 base 摘出来。
    static func rootURL(for panelURL: URL) -> URL? {
        guard var components = URLComponents(url: panelURL, resolvingAgainstBaseURL: false) else { return nil }
        var segments = components.path.split(separator: "/").map(String.init)
        let pageSegments: Set<String> = ["panel", "login", "index.html", "index", "dashboard", "inbounds", "settings", "nodes", "hosts", "clients"]
        while let last = segments.last, pageSegments.contains(last.lowercased()) {
            segments.removeLast()
        }
        components.path = segments.isEmpty ? "/" : "/" + segments.joined(separator: "/") + "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func apiBaseURL(for panelURL: URL) -> URL? {
        guard let root = rootURL(for: panelURL) else { return nil }
        return root.appendingPathComponent("panel").appendingPathComponent("api")
    }

    init(rootURL: URL, apiBaseURL: URL, username: String, password: String, twoFactorCode: String = "", trustSelfSigned: Bool) {
        self.rootURL = rootURL
        self.apiBaseURL = apiBaseURL
        self.username = username
        self.password = password
        self.twoFactorCode = twoFactorCode
        self.trustSelfSigned = trustSelfSigned
        super.init()
    }

    /// 从服务器档案建客户端；地址无效时返回 nil。
    static func make(profile: ServerProfile, username: String, password: String, twoFactorCode: String = "") -> PanelAPIClient? {
        guard let url = profile.url,
              let root = PanelAPIClient.rootURL(for: url),
              let api = PanelAPIClient.apiBaseURL(for: url) else {
            return nil
        }
        return PanelAPIClient(
            rootURL: root,
            apiBaseURL: api,
            username: username,
            password: password,
            twoFactorCode: twoFactorCode,
            trustSelfSigned: profile.trustSelfSigned
        )
    }

    // MARK: - 会话

    func prepareSession(completion: @escaping (PanelAPIError?) -> Void) {
        guard !didAttemptLogin else {
            completion(loginError)
            return
        }
        didAttemptLogin = true

        guard !username.isEmpty || !password.isEmpty else {
            // 没存账号密码：希望网页里已经登录过，cookie 已在共享存储中。
            completion(nil)
            return
        }

        login { [weak self] error in
            self?.loginError = error
            completion(error)
        }
    }

    /// 登录：先取 CSRF 令牌，再带 X-CSRF-Token 发 POST /login。
    /// `attempt` 只在内层重试时用一次：旧令牌导致 403 时换新令牌再试。
    private func login(attempt: Int = 0, completion: @escaping (PanelAPIError?) -> Void) {
        fetchCSRFToken(force: attempt > 0) { [weak self] token in
            guard let self = self else { return }
            let loginURL = self.rootURL.appendingPathComponent("login")
            var request = URLRequest(url: loginURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
            request.httpMethod = "POST"
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = token, !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            }

            var fields = [
                "username=\(PanelAPIClient.formEncode(self.username))",
                "password=\(PanelAPIClient.formEncode(self.password))"
            ]
            let code = self.twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                fields.append("twoFactorCode=\(PanelAPIClient.formEncode(code))")
            }
            request.httpBody = Data(fields.joined(separator: "&").utf8)

            self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.network(error.localizedDescription))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 403 && attempt == 0 {
                    // 令牌与旧 session 对不上（比如网页端重登过）：换一枚再试一次。
                    self.login(attempt: 1, completion: completion)
                    return
                }
                guard (200..<300).contains(status) else {
                    let apiError: PanelAPIError = (status == 401 || status == 403) ? .unauthorized : .http(status)
                    completion(apiError)
                    return
                }
                let succeed: () -> Void = { [weak self] in
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    // 3x-ui 的 SetLoginUser 会把 session 清空重建，旧 CSRF 令牌随之作废，
                    // 丢掉缓存并预取一枚新的，后续写请求直接用。
                    self.csrfToken = nil
                    self.syncCookiesToWebView()
                    self.fetchCSRFToken { _ in }
                    completion(nil)
                }
                guard let data = data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    // 有的版本登录成功返回 HTML 跳转，只要 2xx 就当作登录成功。
                    succeed()
                    return
                }
                let success = InboundSummary.boolean(object["success"]) ?? true
                if success {
                    succeed()
                } else {
                    let message = InboundSummary.string(object["msg"]) ?? "账号或密码不正确"
                    completion(.api(message))
                }
            }.resume()
        }
    }

    // MARK: - CSRF 令牌

    /// 取一次 CSRF 令牌（多个并发请求共用同一次网络请求）。
    /// 已经缓存到就直接回调；`force` 用于令牌失效后重新取。
    /// v2.x 没有 /csrf-token 路由，或者返回的不是 JSON，就回调 nil，照旧版方式请求。
    func fetchCSRFToken(force: Bool = false, completion: @escaping (String?) -> Void) {
        if !force, let token = csrfToken {
            completion(token)
            return
        }
        csrfQueue.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            if !force, let token = self.csrfToken {
                completion(token)
                return
            }
            if self.csrfFetching {
                self.csrfWaiters.append(completion)
                return
            }
            self.csrfFetching = true
            self.requestCSRFToken { token in
                self.csrfQueue.async {
                    self.csrfFetching = false
                    let waiters = self.csrfWaiters
                    self.csrfWaiters = []
                    for waiter in waiters {
                        waiter(token)
                    }
                    completion(token)
                }
            }
        }
    }

    private func requestCSRFToken(completion: @escaping (String?) -> Void) {
        var url = rootURL
        url.appendPathComponent("csrf-token")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil else {
                completion(nil)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // v2.x：404 或返回登录页 HTML，视为没有 CSRF 机制。
                completion(nil)
                return
            }
            let token = (InboundSummary.string(object["obj"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                completion(nil)
                return
            }
            self?.csrfToken = token
            completion(token)
        }.resume()
    }

    /// 原生登录成功后，把 cookie 同步给 WKWebView，让「原版网页」也直接是登录态。
    private func syncCookiesToWebView() {
        let host = rootURL.host ?? ""
        let all = HTTPCookieStorage.shared.cookies ?? []
        var matched: [HTTPCookie] = []
        for cookie in all {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            if host.isEmpty || domain.isEmpty || host == domain || host.hasSuffix(domain) {
                matched.append(cookie)
            }
        }
        guard !matched.isEmpty else { return }
        let cookies = matched
        DispatchQueue.main.async {
            let store = WKWebsiteDataStore.default().httpCookieStore
            for cookie in cookies {
                store.setCookie(cookie, completionHandler: nil)
            }
        }
    }

    // MARK: - 概览

    func fetchOverview(completion: @escaping (Result<PanelOverview, PanelAPIError>) -> Void) {
        prepareSession { [weak self] loginProblem in
            guard let self = self else { return }
            if let loginProblem = loginProblem {
                completion(.failure(loginProblem))
                return
            }

            let collector = OverviewCollector()
            let group = DispatchGroup()

            group.enter()
            self.requestEnvelope(path: "server/status") { result in
                switch result {
                case .success(let object):
                    collector.status = object as? [String: Any]
                case .failure(let error):
                    collector.record(error)
                }
                group.leave()
            }

            group.enter()
            self.requestEnvelope(path: "inbounds/list") { result in
                switch result {
                case .success(let object):
                    collector.inbounds = (object as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
                case .failure(let error):
                    collector.record(error)
                }
                group.leave()
            }

            group.enter()
            self.fetchOnlineEmails { emails in
                collector.onlines = emails
                group.leave()
            }

            group.notify(queue: .main) {
                if let blocking = collector.blockingError {
                    completion(.failure(blocking))
                    return
                }
                let overview = self.makeOverview(
                    status: collector.status,
                    inbounds: collector.inbounds,
                    onlines: collector.onlines
                )
                completion(.success(overview))
            }
        }
    }

    private func makeOverview(status: [String: Any]?, inbounds raw: [[String: Any]], onlines: [String]) -> PanelOverview {
        let status = status ?? [:]
        let mem = InboundSummary.dictionary(status["mem"])
        let disk = InboundSummary.dictionary(status["disk"])
        let xray = InboundSummary.dictionary(status["xray"])
        let netIO = InboundSummary.dictionary(status["netIO"])
        let publicIP = InboundSummary.dictionary(status["publicIP"])

        var uptime = InboundSummary.number(status["uptime"])
        // 3x-ui 的 uptime 是秒；个别老版本/魔改版返回毫秒，看到荒谬的大数就换单位。
        if let value = uptime, value > 315_576_000 {
            uptime = value / 1000
        }

        let parsedInbounds = raw.compactMap { InboundSummary.parse($0) }

        return PanelOverview(
            cpuPercent: InboundSummary.number(status["cpu"]),
            memUsed: InboundSummary.number(mem["current"]) ?? InboundSummary.number(status["memCurrent"]),
            memTotal: InboundSummary.number(mem["total"]) ?? InboundSummary.number(status["memTotal"]),
            diskUsed: InboundSummary.number(disk["current"]) ?? InboundSummary.number(status["diskCurrent"]),
            diskTotal: InboundSummary.number(disk["total"]) ?? InboundSummary.number(status["diskTotal"]),
            uptimeSeconds: uptime,
            xrayState: InboundSummary.string(xray["state"]) ?? "unknown",
            xrayVersion: InboundSummary.string(xray["version"]) ?? "",
            onlineEmails: onlines,
            inbounds: parsedInbounds.sorted { $0.port < $1.port },
            netUp: InboundSummary.number(netIO["up"]),
            netDown: InboundSummary.number(netIO["down"]),
            tcpCount: InboundSummary.number(status["tcpCount"]),
            udpCount: InboundSummary.number(status["udpCount"]),
            publicIPv4: InboundSummary.string(publicIP["ipv4"]) ?? "",
            publicIPv6: InboundSummary.string(publicIP["ipv6"]) ?? "",
            fetchedAt: Date()
        )
    }

    // MARK: - 在线客户端

    /// v2：/inbounds/onlines；v3：/clients/onlines。都拿不到就当没有在线数据。
    private func fetchOnlineEmails(completion: @escaping ([String]) -> Void) {
        requestEnvelope(path: "inbounds/onlines", method: "POST", body: Data("{}".utf8)) { [weak self] result in
            switch result {
            case .success(let object):
                completion(PanelAPIClient.emails(from: object))
            case .failure:
                self?.requestEnvelope(path: "clients/onlines", method: "POST", body: Data("{}".utf8)) { second in
                    switch second {
                    case .success(let object):
                        completion(PanelAPIClient.emails(from: object))
                    case .failure:
                        completion([])
                    }
                }
            }
        }
    }

    static func emails(from object: Any?) -> [String] {
        if let list = object as? [String] {
            return list.filter { !$0.isEmpty }
        }
        if let list = object as? [Any] {
            return list.compactMap { item -> String? in
                if let text = item as? String { return text.isEmpty ? nil : text }
                if let dict = item as? [String: Any] { return InboundSummary.string(dict["email"]) }
                return nil
            }
        }
        if let dict = object as? [String: Any] {
            return dict.keys.sorted()
        }
        return []
    }

    // MARK: - 启用 / 停用

    func setInbound(_ inbound: InboundSummary, enabled: Bool, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        var body = inbound.raw
        body["enable"] = enabled
        body["id"] = inbound.id

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(.decoding("入站数据无法序列化")))
            return
        }

        requestEnvelope(path: "inbounds/update/\(inbound.id)", method: "POST", body: data) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                // 新版把启停独立成 setEnable/:id，老版本没有；互为兜底。
                let fallbackBody = try? JSONSerialization.data(withJSONObject: ["enable": enabled], options: [])
                self?.requestEnvelope(path: "inbounds/setEnable/\(inbound.id)", method: "POST", body: fallbackBody ?? Data("{}".utf8)) { second in
                    switch second {
                    case .success:
                        completion(.success(()))
                    case .failure:
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    // MARK: - 数据库备份

    func downloadDatabase(completion: @escaping (Result<URL, PanelAPIError>) -> Void) {
        prepareSession { [weak self] loginProblem in
            guard let self = self else { return }
            if let loginProblem = loginProblem {
                completion(.failure(loginProblem))
                return
            }
            var url = self.apiBaseURL
            url.appendPathComponent("server")
            url.appendPathComponent("getDb")
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            request.httpMethod = "GET"
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

            self.session.downloadTask(with: request) { location, response, error in
                if let error = error {
                    completion(.failure(.network(error.localizedDescription)))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status), let location = location else {
                    let apiError: PanelAPIError = (status == 401 || status == 403) ? .unauthorized : .http(status)
                    completion(.failure(apiError))
                    return
                }
                let stamp = Int(Date().timeIntervalSince1970)
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XUIBackup", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                let destination = directory.appendingPathComponent("x-ui-backup-\(stamp).db")
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    completion(.success(destination))
                } catch {
                    completion(.failure(.network("保存备份失败：\(error.localizedDescription)")))
                }
            }.resume()
        }
    }

    // MARK: - 请求

    func requestEnvelope(path: String, method: String = "GET", body: Data? = nil, completion: @escaping (Result<Any, PanelAPIError>) -> Void) {
        var url = apiBaseURL
        for component in path.split(separator: "/") where !component.isEmpty {
            url.appendPathComponent(String(component))
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        perform(request, completion: completion)
    }

    func perform(_ request: URLRequest, completion: @escaping (Result<Any, PanelAPIError>) -> Void) {
        sendWithCSRF(request, canRetry: true, completion: completion)
    }

    /// 所有请求的统一入口：
    /// 1. 一律带 X-Requested-With（api.go 靠它把未登录区分为 401 而不是 404）；
    /// 2. 写请求带 X-CSRF-Token，还没令牌就先取（网页登录后回来的场景）；
    /// 3. 写请求 403 时换一枚新令牌重放一次。
    private func sendWithCSRF(_ original: URLRequest, canRetry: Bool, completion: @escaping (Result<Any, PanelAPIError>) -> Void) {
        var request = original
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        guard !PanelAPIClient.isSafeMethod(request.httpMethod ?? "GET") else {
            sendRaw(request, canRetry: false, completion: completion)
            return
        }
        if let token = csrfToken {
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            sendRaw(request, canRetry: canRetry, completion: completion)
            return
        }
        // 没有令牌（第一次写操作，或刚从网页登录回来）：先取一次再发。
        fetchCSRFToken { [weak self] token in
            guard let self = self else { return }
            var ready = original
            ready.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            if let token = token {
                ready.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            }
            self.sendRaw(ready, canRetry: canRetry, completion: completion)
        }
    }

    private func sendRaw(_ request: URLRequest, canRetry: Bool, completion: @escaping (Result<Any, PanelAPIError>) -> Void) {
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // CSRF 令牌失效：取新令牌重放一次，再失败才算真失败。
            if status == 403, canRetry, let self = self,
               !PanelAPIClient.isSafeMethod(request.httpMethod ?? "GET") {
                self.fetchCSRFToken(force: true) { token in
                    var retry = request
                    if let token = token {
                        retry.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
                    }
                    self.sendRaw(retry, canRetry: false, completion: completion)
                }
                return
            }
            guard status != 401 && status != 403 else {
                completion(.failure(.unauthorized))
                return
            }
            guard (200..<300).contains(status) else {
                completion(.failure(.http(status)))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.success(NSNull()))
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // 未登录时有的版本直接返回登录页 HTML。
                completion(.failure(.unauthorized))
                return
            }
            let success = InboundSummary.boolean(object["success"]) ?? true
            let message = InboundSummary.string(object["msg"]) ?? ""
            if !success {
                let lower = message.lowercased()
                if lower.contains("login") || message.contains("登录") || message.contains("登陆") {
                    completion(.failure(.unauthorized))
                } else {
                    completion(.failure(.api(message.isEmpty ? "面板返回失败" : message)))
                }
                return
            }
            completion(.success(object["obj"] ?? NSNull()))
        }.resume()
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - 自签证书

    private func handle(challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust {
            if trustSelfSigned, let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

extension PanelAPIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }
}

extension PanelAPIClient: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }
}

/// 并发收三个接口的结果，串行回调队列上写，不会打架。
private final class OverviewCollector {
    var status: [String: Any]?
    var inbounds: [[String: Any]] = []
    var onlines: [String] = []
    private(set) var blockingError: PanelAPIError?

    func record(_ error: PanelAPIError) {
        if case .unauthorized = error {
            blockingError = blockingError ?? error
        }
        // 其它错误（比如某个接口不存在）忽略，能拿多少显示多少。
    }
}

/// 从 WKWebView 的 cookie 仓库里取出匹配当前站点的 cookie，塞进共享存储，
/// 这样即使用户没保存账号密码、但网页里已登录，快捷概览也能直接用。
enum WebCookieReader {
    static func seedCookies(for url: URL, completion: @escaping () -> Void) {
        let host = url.host ?? ""
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                if !host.isEmpty && (host == domain || host.hasSuffix(domain)) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
            DispatchQueue.main.async { completion() }
        }
    }
}
