import Foundation

/// 面板使用的 User-Agent 偏好：电脑版（桌面 Safari）或手机版（WKWebView 默认）。
enum UserAgentMode: String, Codable, CaseIterable, Identifiable {
    case desktop
    case mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "电脑版"
        case .mobile: return "手机版"
        }
    }

    var shortTitle: String {
        switch self {
        case .desktop: return "桌面 UA"
        case .mobile: return "手机 UA"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .mobile: return "iphone"
        }
    }
}

/// 一台 3x-ui 服务器的配置。
///
/// 注意：密码（以及可选的用户名）从不写入这个结构体，也不会进 JSON 存档，
/// 而是按 `id` 存在钥匙串里，见 `ServerStore.credentials(for:)`。
struct ServerProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var urlString: String
    var username: String
    var trustSelfSigned: Bool
    var userAgent: UserAgentMode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        username: String = "",
        trustSelfSigned: Bool = false,
        userAgent: UserAgentMode = .desktop,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.username = username
        self.trustSelfSigned = trustSelfSigned
        self.userAgent = userAgent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 规整后的面板地址：没写协议时补 `https://`，只接受 http / https。
    var url: URL? {
        ServerProfile.normalize(urlString)
    }

    var host: String {
        guard let url = url else { return urlString }
        var host = url.host ?? urlString
        if let port = url.port { host += ":\(port)" }
        return host
    }

    var path: String {
        guard let url = url else { return "" }
        let p = url.path
        return p == "/" ? "" : p
    }

    var hostAndPath: String {
        host + path
    }

    var isUsingHTTP: Bool {
        url?.scheme?.lowercased() == "http"
    }

    /// 印章里用的一个字：取名字的首字，名字空时用「墨」。
    var sealCharacter: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first)
        }
        return "墨"
    }

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

/// 编辑器里的临时草稿（含明文密码，只在内存里短暂存在）。
struct ServerDraft: Identifiable {
    var id: UUID
    var name: String
    var urlString: String
    var username: String
    var password: String
    var trustSelfSigned: Bool
    var userAgent: UserAgentMode

    init(profile: ServerProfile? = nil, password: String = "", defaultUserAgent: UserAgentMode = .desktop) {
        if let profile = profile {
            self.id = profile.id
            self.name = profile.name
            self.urlString = profile.urlString
            self.username = profile.username
            self.password = password
            self.trustSelfSigned = profile.trustSelfSigned
            self.userAgent = profile.userAgent
        } else {
            self.id = UUID()
            self.name = ""
            self.urlString = ""
            self.username = ""
            self.password = ""
            self.trustSelfSigned = false
            self.userAgent = defaultUserAgent
        }
    }

    /// 生成保存用的服务器档案（密码另外进钥匙串）。
    func makeProfile(existingCreatedAt: Date? = nil) -> ServerProfile {
        ServerProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            trustSelfSigned: trustSelfSigned,
            userAgent: userAgent,
            createdAt: existingCreatedAt ?? Date(),
            updatedAt: Date()
        )
    }

    var normalizedURL: URL? {
        ServerProfile.normalize(urlString)
    }

    /// 标题为空时用主机名兜底，保证列表里不会出现空白行。
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let url = normalizedURL {
            return url.host ?? urlString
        }
        return urlString
    }
}
