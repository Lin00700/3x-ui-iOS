import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: LockManager
    @Environment(\.dismiss) private var dismiss

    @State private var clearedWebData = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        privacySection
                        displaySection
                        webDataSection
                        aboutSection
                    }
                    .padding(18)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Ink.cinnabar)
                }
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
    }

    // MARK: - 隐私

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("隐私")

            InkCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.privacyLockEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("隐私锁")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Ink.ink)
                            Text("启动与回到前台时，用\(lock.biometryName)或设备密码解锁")
                                .font(.system(size: 11))
                                .foregroundColor(Ink.inkFaint)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Ink.moss))
                    .onChange(of: settings.privacyLockEnabled) { enabled in
                        if enabled && !lock.isLocked {
                            lock.lock()
                        }
                    }

                    Text("面板地址与账号都存在本机：地址在 App 沙盒里，密码在 iOS 钥匙串。开启隐私锁后，别人拿到已解锁的手机也看不到它们。")
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 显示

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("新服务器的默认显示")

            InkCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("默认显示", selection: $settings.defaultUserAgent) {
                        ForEach(UserAgentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text("电脑版按 1280 宽渲染，适合看表格与大批客户端；手机版交给 3x-ui 的响应式布局。每台服务器还能单独覆盖。")
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 网页数据

    private var webDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("网页数据")

            InkCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        clearWebData()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text(clearedWebData ? "已清除所有面板的 Cookie 与缓存" : "清除 Cookie 与缓存")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(clearedWebData ? Ink.moss : Ink.cinnabar)
                    }

                    Text("会把所有面板的登录状态一起清掉，下次打开需要重新登录。适合面板换了路径或一直卡在旧页面时使用。")
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("关于")

            InkCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        InkSeal(text: "三", size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("3x-ui 面板")
                                .font(Ink.serif(15, .semibold))
                                .foregroundColor(Ink.ink)
                            Text("版本 \(versionText)")
                                .font(.system(size: 11))
                                .foregroundColor(Ink.inkFaint)
                        }
                        Spacer()
                    }

                    Text("把 VPS 上的 3x-ui 网页完整装进手机：网页原样保留，外面加一层水墨色的工具栏、快捷概览与隐私锁。App 本身不代理任何流量，也不保存你的节点配置。")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: "https://github.com/Lin00700/3x-ui-iOS") {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("github.com/Lin00700/3x-ui-iOS")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(Ink.indigo)
                    }
                }
            }

            Text("提示：面板用 http:// 或自签 HTTPS 时，记得在服务器设置里打开「信任自签证书」，否则 WebView 会拦截连接。")
                .font(.system(size: 10.5))
                .foregroundColor(Ink.inkFaint)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Ink.serif(14, .semibold))
            .foregroundColor(Ink.inkSoft)
            .padding(.horizontal, 4)
    }

    private func clearWebData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            DispatchQueue.main.async {
                clearedWebData = true
            }
        }
    }
}
