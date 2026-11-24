import Foundation
import SwiftUI

/// 服务器档案的内存 + 磁盘仓库。磁盘上只有不含密码的 JSON。
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryName: String = "XUIPanel") {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        self.fileURL = directory.appendingPathComponent("servers.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([ServerProfile].self, from: data) {
            servers = decoded.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(servers) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // 备份文件对找问题的用户更方便，也避免写到一半损坏时全丢。
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("servers.backup.json")
        try? data.write(to: backup, options: .atomic)
    }

    // MARK: - 查询

    var isEmpty: Bool { servers.isEmpty }

    func profile(with id: UUID) -> ServerProfile? {
        servers.first(where: { $0.id == id })
    }

    /// 钥匙串里的凭据；没存过返回空串。
    func credentials(for id: UUID) -> (username: String, password: String) {
        let password = KeychainStore.get(account: KeychainStore.passwordAccount(for: id)) ?? ""
        let storedUsername = KeychainStore.get(account: KeychainStore.usernameAccount(for: id))
        let username = storedUsername ?? (profile(with: id)?.username ?? "")
        return (username, password)
    }

    func password(for id: UUID) -> String {
        KeychainStore.get(account: KeychainStore.passwordAccount(for: id)) ?? ""
    }

    func hasSavedLogin(for id: UUID) -> Bool {
        let credentials = self.credentials(for: id)
        return !credentials.username.isEmpty || !credentials.password.isEmpty
    }

    // MARK: - 修改

    @discardableResult
    func save(draft: ServerDraft) -> ServerProfile {
        let existing = profile(with: draft.id)
        var profile = draft.makeProfile(existingCreatedAt: existing?.createdAt)
        if profile.name.isEmpty {
            profile.name = draft.resolvedName
        }

        KeychainStore.set(draft.username, account: KeychainStore.usernameAccount(for: profile.id))
        KeychainStore.set(draft.password, account: KeychainStore.passwordAccount(for: profile.id))

        if let index = servers.firstIndex(where: { $0.id == profile.id }) {
            servers[index] = profile
        } else {
            servers.append(profile)
        }
        persist()
        return profile
    }

    func delete(id: UUID) {
        servers.removeAll(where: { $0.id == id })
        KeychainStore.delete(account: KeychainStore.passwordAccount(for: id))
        KeychainStore.delete(account: KeychainStore.usernameAccount(for: id))
        persist()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { servers.indices.contains($0) ? servers[$0].id : nil }
        for id in ids {
            delete(id: id)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        servers.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func moveToTop(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let profile = servers.remove(at: index)
        servers.insert(profile, at: 0)
        persist()
    }

    /// 只更新网页相关的偏好（UA、自签信任），不动钥匙串。
    func updatePreferences(id: UUID, userAgent: UserAgentMode? = nil, trustSelfSigned: Bool? = nil) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        if let userAgent = userAgent {
            servers[index].userAgent = userAgent
        }
        if let trustSelfSigned = trustSelfSigned {
            servers[index].trustSelfSigned = trustSelfSigned
        }
        servers[index].updatedAt = Date()
        persist()
    }
}

/// 全局偏好：隐私锁、默认 UA。
final class AppSettings: ObservableObject {
    private enum Keys {
        static let privacyLock = "xui.privacyLockEnabled"
        static let defaultUserAgent = "xui.defaultUserAgent"
    }

    private let defaults: UserDefaults

    @Published var privacyLockEnabled: Bool {
        didSet { defaults.set(privacyLockEnabled, forKey: Keys.privacyLock) }
    }

    @Published var defaultUserAgent: UserAgentMode {
        didSet { defaults.set(defaultUserAgent.rawValue, forKey: Keys.defaultUserAgent) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.privacyLockEnabled = defaults.bool(forKey: Keys.privacyLock)
        if let raw = defaults.string(forKey: Keys.defaultUserAgent), let mode = UserAgentMode(rawValue: raw) {
            self.defaultUserAgent = mode
        } else {
            self.defaultUserAgent = .desktop
        }
    }
}
