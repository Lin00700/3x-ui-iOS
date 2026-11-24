import Foundation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// 从页面里抓出来的一张二维码。
struct QRCodeItem: Identifiable, Hashable {
    let id = UUID()
    var source: String
    var width: CGFloat
    var height: CGFloat
}

/// 3x-ui 面板的 WebView 控制器：持有唯一一个 WKWebView，
/// 负责加载、UA 切换、自签证书放行、登录填充、下载与文件上传。
final class PanelWebController: NSObject, ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var pageTitle = ""
    @Published private(set) var currentURLString = ""
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var userAgentMode: UserAgentMode
    @Published var lastError: String?
    @Published var toast: String?
    @Published var subscriptionLinks: [String] = []
    @Published var subscriptionCodes: [QRCodeItem] = []
    @Published var showsSubscriptions = false

    let webView: WKWebView
    private(set) var profile: ServerProfile

    private var username: String
    private var password: String
    private var observations: [NSKeyValueObservation] = []
    private var toastWorkItem: DispatchWorkItem?
    private var pendingOpenPanel: (([URL]?) -> Void)?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    init(profile: ServerProfile, username: String, password: String) {
        self.profile = profile
        self.username = username
        self.password = password
        self.userAgentMode = profile.userAgent

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = UserAgent.string(for: profile.userAgent)
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.965, green: 0.953, blue: 0.925, alpha: 1)
        webView.allowsLinkPreview = true
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
    }

    deinit {
        observations.forEach { $0.invalidate() }
        toastWorkItem?.cancel()
    }

    // MARK: - 加载

    func load() {
        guard let url = profile.url else {
            lastError = "地址无效，请检查是否填写 http(s):// 与端口，例如 https://1.2.3.4:2053/path"
            return
        }
        lastError = nil
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    func load(profile: ServerProfile, username: String, password: String) {
        self.profile = profile
        self.username = username
        self.password = password
        self.userAgentMode = profile.userAgent
        webView.customUserAgent = UserAgent.string(for: profile.userAgent)
        lastError = nil
        load()
    }

    func reload() {
        if webView.url == nil {
            load()
        } else {
            lastError = nil
            webView.reload()
        }
    }

    func stop() {
        webView.stopLoading()
        isLoading = false
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func goHome() {
        load()
    }

    // MARK: - UA / 视口

    func toggleUserAgent() {
        setUserAgent(userAgentMode == .desktop ? .mobile : .desktop)
    }

    func setUserAgent(_ mode: UserAgentMode) {
        userAgentMode = mode
        webView.customUserAgent = UserAgent.string(for: mode)
        if let current = webView.url {
            var request = URLRequest(url: current, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            webView.load(request)
        } else {
            load()
        }
        showToast(mode == .desktop ? "已切到电脑版布局" : "已切到手机版布局")
    }

    private func applyViewport() {
        let script = userAgentMode == .desktop ? ViewportMode.desktopJS : ViewportMode.mobileJS
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - 登录填充

    func hasSavedLogin() -> Bool {
        !username.isEmpty || !password.isEmpty
    }

    func fillSavedLogin() {
        guard hasSavedLogin() else {
            showToast("这台服务器还没有保存账号密码")
            return
        }
        let script = InjectedScripts.fillLogin(user: username, password: password)
        webView.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.showToast("填入失败：\(error.localizedDescription)")
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.showToast("已在页面上尝试填入，请检查登录框")
                    return
                }
                let userFilled = object["user"] as? Bool ?? false
                let passFilled = object["password"] as? Bool ?? false
                if userFilled || passFilled {
                    self.showToast("已填入账号密码，点「登录」即可")
                } else {
                    self.showToast("没找到登录框，先打开 3x-ui 登录页")
                }
            }
        }
    }

    // MARK: - 订阅 / 二维码

    func extractSubscriptions() {
        webView.evaluateJavaScript(InjectedScripts.extractLinks) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.showToast("提取失败：\(error.localizedDescription)")
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.showToast("页面里没有找到订阅链接")
                    return
                }
                let links = (object["links"] as? [String]) ?? []
                let rawCodes = (object["qrs"] as? [[String: Any]]) ?? []
                self.subscriptionLinks = links
                self.subscriptionCodes = rawCodes.compactMap { item in
                    guard let source = item["src"] as? String, !source.isEmpty else { return nil }
                    let width = (item["width"] as? NSNumber)?.doubleValue ?? 0
                    let height = (item["height"] as? NSNumber)?.doubleValue ?? 0
                    return QRCodeItem(source: source, width: CGFloat(width), height: CGFloat(height))
                }
                if links.isEmpty && self.subscriptionCodes.isEmpty {
                    self.showToast("当前页面没有订阅链接或二维码")
                } else {
                    self.showsSubscriptions = true
                }
            }
        }
    }

    // MARK: - 地址 / 数据

    var displayURL: String {
        if !currentURLString.isEmpty { return currentURLString }
        return profile.url?.absoluteString ?? profile.urlString
    }

    func copyCurrentURL() {
        UIHelpers.copyToPasteboard(displayURL)
        showToast("地址已复制")
    }

    func shareCurrentURL() {
        guard let url = URL(string: displayURL) else {
            showToast("当前没有可分享的地址")
            return
        }
        UIHelpers.share(items: [url])
    }

    func openInSafari() {
        guard let url = webView.url ?? profile.url else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.showToast("已清除 Cookie 与缓存，正在重新打开")
                self.load()
            }
        }
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - 提示条

    func showToast(_ text: String) {
        DispatchQueue.main.async {
            self.toast = text
            self.toastWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.toast = nil
            }
            self.toastWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: item)
        }
    }

    // MARK: - KVO

    private func observeWebView() {
        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
        })
        observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
        })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.isLoading = view.isLoading }
        })
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.progress = view.estimatedProgress }
        })
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.pageTitle = view.title ?? "" }
        })
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentURLString = view.url?.absoluteString ?? ""
                self.hasLoadedOnce = view.url != nil
            }
        })
    }

    // MARK: - 下载

    private func downloadDirectory() -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("XUIDownloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        }
        return base
    }

    private func shareDownloadedFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        UIHelpers.share(items: [url])
    }
}

// MARK: - WKNavigationDelegate

extension PanelWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.lastError = nil
            self.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.currentURLString = webView.url?.absoluteString ?? self.currentURLString
            self.hasLoadedOnce = true
        }
        applyViewport()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.lastError = "网页进程被系统回收，已尝试重新加载"
        }
        webView.reload()
    }

    private func handle(_ error: Error) {
        let nsError = error as NSError
        // -999 是用户主动打断（例如点了切换服务器），不当作错误展示。
        guard nsError.code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isLoading = false
            self.lastError = self.friendlyMessage(for: nsError)
        }
    }

    private func friendlyMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorCannotFindHost:
            return "找不到这个域名，检查地址是否写对"
        case NSURLErrorCannotConnectToHost:
            return "连不上服务器，检查端口是否开放、面板是否在运行"
        case NSURLErrorTimedOut:
            return "连接超时，服务器可能不可达或网络被限制"
        case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
            return "证书不被信任。如果面板是自签证书，请在服务器设置里打开「信任自签证书」"
        case NSURLErrorNotConnectedToInternet:
            return "设备当前没有网络"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "系统拦截了不安全的 HTTP 连接"
        default:
            return "加载失败：\(error.localizedDescription)"
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod

        if method == NSURLAuthenticationMethodServerTrust {
            if profile.trustSelfSigned, let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
            if !username.isEmpty {
                let credential = URLCredential(user: username, password: password, persistence: .forSession)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            // tel: / mailto: / v2ray: 之类交给系统或其它 App。
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        // target="_blank" 的链接在同一个 WebView 里打开，避免什么都没发生。
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let name = (response.suggestedFilename ?? "").lowercased()
        let mime = (response.mimeType ?? "").lowercased()
        let downloadExtensions = ["db", "sqlite", "zip", "tar", "gz", "tgz", "bak", "conf", "json", "log", "csv", "yaml", "yml", "txt", "sh", "pem", "crt", "key", "xlsx"]
        let looksLikeFile = downloadExtensions.contains(where: { name.hasSuffix("." + $0) })
        let isBinary = mime == "application/octet-stream" || mime.hasPrefix("application/zip") || mime.hasPrefix("application/x-tar")

        if navigationResponse.isForMainFrame {
            // 主文档永远是面板页面本身，不拦。
            decisionHandler(.allow)
            return
        }
        if !navigationResponse.canShowMIMEType || looksLikeFile || isBinary {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension PanelWebController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: pageTitle.isEmpty ? "面板提示" : pageTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        UIHelpers.present(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: pageTitle.isEmpty ? "面板提示" : pageTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        UIHelpers.present(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: pageTitle.isEmpty ? "面板提示" : pageTitle, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        UIHelpers.present(alert)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        pendingOpenPanel = completionHandler
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        UIHelpers.present(picker)
    }
}

// MARK: - 文件选择 / 下载

extension PanelWebController: UIDocumentPickerDelegate, WKDownloadDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pendingOpenPanel?(urls)
        pendingOpenPanel = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingOpenPanel?(nil)
        pendingOpenPanel = nil
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let safeName = suggestedFilename.isEmpty ? "x-ui-download" : suggestedFilename
        var destination = downloadDirectory().appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            destination = downloadDirectory().appendingPathComponent("\(base)-\(stamp).\(ext)")
        }
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard let destination = downloadDestinations[key] else {
            showToast("下载完成")
            return
        }
        downloadDestinations.removeValue(forKey: key)
        showToast("已下载 \(destination.lastPathComponent)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.shareDownloadedFile(at: destination)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        showToast("下载失败：\(error.localizedDescription)")
    }
}
