import Foundation
import Combine

/// 原生 App UI 的数据与动作中心：一次登录，四个页签共用。
final class PanelSession: ObservableObject {
    @Published private(set) var profile: ServerProfile
    @Published private(set) var inbounds: [InboundSummary] = []
    @Published var overview: PanelOverview?
    @Published var panelSettings: PanelSettingsInfo?
    @Published var isLoading = false
    @Published var isWorking = false
    @Published var errorText: String?
    @Published var needsLogin = false
    @Published var loginError: String?
    @Published var toast: String?
    @Published var lastUpdated: Date?
    @Published var logs: [String] = []
    @Published var isLoadingLogs = false
    @Published var logError: String?

    @Published var autoRefresh: Bool = true {
        didSet { restartTimer() }
    }

    /// 登录成功后把账号密码交回给上层存进钥匙串。
    var onSaveCredentials: ((UUID, String, String) -> Void)?

    private(set) var client: PanelAPIClient?
    private var username: String
    private var password: String
    /// 两步验证码（TOTP）随时效变，不存钥匙串，只在本次会话里用。
    private var twoFactorCode: String
    private var started = false
    private var settingsLoaded = false
    private var timer: Timer?
    private var toastItem: DispatchWorkItem?

    init(profile: ServerProfile, username: String, password: String, twoFactorCode: String = "") {
        self.profile = profile
        self.username = username
        self.password = password
        self.twoFactorCode = twoFactorCode
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 派生

    var hasCredentials: Bool {
        !username.isEmpty || !password.isEmpty
    }

    var linkHost: String {
        if let ip = overview?.publicIPv4, !ip.isEmpty { return ip }
        if let ip = overview?.publicIPv6, !ip.isEmpty { return ip }
        return profile.url?.host ?? ""
    }

    var nodes: [ShareNode] {
        var result: [ShareNode] = []
        for inbound in inbounds {
            for client in inbound.clients {
                let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: linkHost)
                let sub = ShareLinkBuilder.subscriptionURL(
                    subId: client.subId,
                    settings: panelSettings,
                    panelURL: profile.url
                )
                result.append(ShareNode(inbound: inbound, client: client, link: link, subscription: sub))
            }
        }
        return result
    }

    var totalClients: Int {
        var count = 0
        for inbound in inbounds {
            count += inbound.clients.count
        }
        return count
    }

    func inbound(withId id: Int) -> InboundSummary? {
        inbounds.first(where: { $0.id == id })
    }

    private func index(of id: Int) -> Int? {
        inbounds.firstIndex(where: { $0.id == id })
    }

    // MARK: - 加载

    func start() {
        if started {
            refresh()
            return
        }
        started = true

        guard let url = profile.url else {
            errorText = "服务器地址无效"
            return
        }

        isLoading = true
        WebCookieReader.seedCookies(for: url) { [weak self] in
            guard let self = self else { return }
            guard let client = PanelAPIClient.make(profile: self.profile, username: self.username, password: self.password, twoFactorCode: self.twoFactorCode) else {
                self.isLoading = false
                self.errorText = "地址无效，无法定位面板 API"
                return
            }
            self.client = client
            self.refresh()
            self.restartTimer()
        }
    }

    func refresh(quiet: Bool = false) {
        guard let client = client else {
            start()
            return
        }
        if !quiet {
            isLoading = true
        }
        errorText = nil

        client.fetchOverview { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let overview):
                    self.overview = overview
                    self.inbounds = overview.inbounds
                    self.lastUpdated = Date()
                    self.needsLogin = false
                    self.errorText = nil
                    if !self.settingsLoaded {
                        self.loadSettings()
                    }
                case .failure(let error):
                    if case .unauthorized = error {
                        self.needsLogin = true
                    }
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    /// 从网页面板回来时把新 cookie 抄过来，再刷新一次。
    func reseedWebCookiesAndRefresh() {
        guard let url = profile.url else { return }
        WebCookieReader.seedCookies(for: url) { [weak self] in
            self?.refresh(quiet: true)
        }
    }

    func loadSettings() {
        guard let client = client else { return }
        client.fetchPanelSettings { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let settings):
                    self.panelSettings = settings
                    self.settingsLoaded = true
                case .failure:
                    break
                }
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard autoRefresh, started else { return }
        let created = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isLoading || self.isWorking { return }
            self.refresh(quiet: true)
        }
        timer = created
    }

    // MARK: - 登录

    func login(username: String, password: String, twoFactorCode: String = "", completion: @escaping (Bool) -> Void) {
        let code = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fresh = PanelAPIClient.make(profile: profile, username: username, password: password, twoFactorCode: code) else {
            loginError = "地址无效，无法定位面板 API"
            completion(false)
            return
        }
        isWorking = true
        loginError = nil

        fresh.fetchOverview { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success(let overview):
                    self.client = fresh
                    self.username = username
                    self.password = password
                    self.twoFactorCode = code
                    self.overview = overview
                    self.inbounds = overview.inbounds
                    self.lastUpdated = Date()
                    self.needsLogin = false
                    self.errorText = nil
                    self.loginError = nil
                    self.settingsLoaded = false
                    self.loadSettings()
                    self.onSaveCredentials?(self.profile.id, username, password)
                    self.restartTimer()
                    completion(true)
                case .failure(let error):
                    self.loginError = error.localizedDescription
                    completion(false)
                }
            }
        }
    }

    func switchProfile(_ next: ServerProfile, username: String, password: String) {
        timer?.invalidate()
        timer = nil
        profile = next
        self.username = username
        self.password = password
        twoFactorCode = ""
        client = nil
        overview = nil
        inbounds = []
        panelSettings = nil
        settingsLoaded = false
        logs = []
        errorText = nil
        loginError = nil
        needsLogin = false
        lastUpdated = nil
        started = false
        start()
    }

    // MARK: - 入站操作

    func setEnabled(_ inbound: InboundSummary, enabled: Bool) {
        guard let client = client, !isWorking else { return }
        // 先乐观更新界面，失败再回滚，避免开关在请求期间弹回去。
        if let index = index(of: inbound.id) {
            inbounds[index].enabled = enabled
        }
        isWorking = true

        client.setInbound(inbound, enabled: enabled) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast(enabled ? "已启用这个入站" : "已停用这个入站")
                    self.refresh(quiet: true)
                case .failure(let error):
                    if let index = self.index(of: inbound.id) {
                        self.inbounds[index].enabled = inbound.enabled
                    }
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    func addInbound(draft: InboundDraft, completion: @escaping (Result<Void, PanelAPIError>) -> Void) {
        guard let client = client else {
            completion(.failure(.network("尚未连接面板")))
            return
        }
        let payload: [String: Any]
        do {
            payload = try draft.makePayload()
        } catch {
            completion(.failure(.api(error.localizedDescription)))
            return
        }

        isWorking = true
        client.addInbound(payload: payload) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("入站已创建")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
                completion(result)
            }
        }
    }

    func updateInbound(id: Int, remark: String, port: Int, enabled: Bool, completion: @escaping (Bool) -> Void) {
        guard let client = client, let inbound = inbound(withId: id) else {
            completion(false)
            return
        }
        var body = inbound.raw
        body.removeValue(forKey: "clientStats")
        body["remark"] = remark
        body["port"] = port
        body["enable"] = enabled
        body["id"] = id

        isWorking = true
        client.updateInbound(id: id, payload: body) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("入站已保存")
                    self.refresh(quiet: true)
                    completion(true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    func deleteInbound(_ inbound: InboundSummary, completion: @escaping (Bool) -> Void) {
        guard let client = client else {
            completion(false)
            return
        }
        isWorking = true
        client.deleteInbound(id: inbound.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.inbounds.removeAll(where: { $0.id == inbound.id })
                    self.showToast("入站已删除")
                    self.refresh(quiet: true)
                    completion(true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    func resetInboundTraffics(_ inbound: InboundSummary) {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.resetInboundTraffics(id: inbound.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("这个入站的流量已清零")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 客户端操作

    func addClient(to inbound: InboundSummary, draft: ClientDraft, completion: @escaping (Bool) -> Void) {
        guard let client = client else {
            completion(false)
            return
        }
        let settingsJSON: String
        do {
            settingsJSON = try draft.makeSettingsJSON(inbound: inbound)
        } catch {
            showToast(error.localizedDescription)
            completion(false)
            return
        }
        isWorking = true
        client.addClient(inboundId: inbound.id, settingsJSON: settingsJSON) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("客户端已添加")
                    self.refresh(quiet: true)
                    completion(true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    func deleteClient(inbound: InboundSummary, client target: ClientSummary, completion: @escaping (Bool) -> Void) {
        guard let client = client else {
            completion(false)
            return
        }
        let identifier = target.identifier.isEmpty ? target.email : target.identifier
        isWorking = true
        client.deleteClient(inboundId: inbound.id, clientId: identifier) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.isWorking = false
                    self.showToast("客户端已删除")
                    self.refresh(quiet: true)
                    completion(true)
                case .failure:
                    // uuid / password 认不出来时，很多版本用邮箱也能定位。
                    self.client?.deleteClient(inboundId: inbound.id, clientId: target.email) { [weak self] second in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            self.isWorking = false
                            switch second {
                            case .success:
                                self.showToast("客户端已删除")
                                self.refresh(quiet: true)
                                completion(true)
                            case .failure(let error):
                                self.showToast(error.localizedDescription)
                                completion(false)
                            }
                        }
                    }
                }
            }
        }
    }

    func resetClientTraffic(inbound: InboundSummary, client target: ClientSummary) {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.resetClientTraffic(inboundId: inbound.id, email: target.email) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("已清零这个客户端的用量")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    /// 客户端启停沿用入站的 updateClient：把这份客户端原样发回去，只改 enable。
    func setClientEnabled(inbound: InboundSummary, client target: ClientSummary, enabled: Bool) {
        guard let client = client, !isWorking else { return }

        var dict: [String: Any] = [
            "email": target.email,
            "enable": enabled,
            "limitIp": 0,
            "totalGB": target.total,
            "expiryTime": target.expiryTime,
            "tgId": "",
            "subId": target.subId
        ]
        switch inbound.protocolName {
        case "trojan", "shadowsocks":
            dict["password"] = target.identifier
        default:
            dict["id"] = target.identifier
            if !target.flow.isEmpty { dict["flow"] = target.flow }
            if inbound.protocolName == "vmess" { dict["alterId"] = 0 }
        }
        if inbound.protocolName == "shadowsocks" {
            dict["method"] = target.method.isEmpty ? "aes-256-gcm" : target.method
        }

        let settings: [String: Any] = ["clients": [dict]]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: []),
              let text = String(data: data, encoding: .utf8) else {
            showToast("客户端设置无法序列化")
            return
        }

        isWorking = true
        client.updateClient(inboundId: inbound.id, clientId: target.identifier, settingsJSON: text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast(enabled ? "客户端已启用" : "客户端已停用")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 维护

    func restartXray() {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.restartXray { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("已发送重启 Xray 指令")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    func restartPanel() {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.restartPanel { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("面板正在重启，稍等再刷新")
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    func resetAllTraffics() {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.resetAllTraffics { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success:
                    self.showToast("全部流量已重置")
                    self.refresh(quiet: true)
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 日志

    func loadLogs(xray: Bool, count: Int) {
        guard let client = client else { return }
        isLoadingLogs = true
        logError = nil
        client.fetchLogs(xray: xray, count: count) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingLogs = false
                switch result {
                case .success(let lines):
                    self.logs = lines
                case .failure(let error):
                    self.logError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 备份

    func downloadDatabase() {
        guard let client = client, !isWorking else { return }
        isWorking = true
        client.downloadDatabase { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorking = false
                switch result {
                case .success(let url):
                    self.showToast("数据库已下载")
                    UIHelpers.share(items: [url])
                case .failure(let error):
                    self.showToast(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 提示

    func showToast(_ text: String) {
        toast = text
        toastItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.toast = nil
        }
        toastItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item)
    }
}
