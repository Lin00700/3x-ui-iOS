import SwiftUI

/// 原版 3x-ui 网页面板 + 水墨外壳工具栏。
struct PanelScreen: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var lock: LockManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var controller: PanelWebController
    @State private var currentProfile: ServerProfile
    @State private var showToolbar = true
    @State private var showSwitcher = false
    @State private var showQuick = false
    @State private var confirmClear = false
    @State private var didAppear = false

    init(profile: ServerProfile, username: String, password: String) {
        _controller = StateObject(wrappedValue: PanelWebController(profile: profile, username: username, password: password))
        _currentProfile = State(initialValue: profile)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                if controller.isLoading {
                    ProgressView(value: min(max(controller.progress, 0.02), 1))
                        .progressViewStyle(LinearProgressViewStyle(tint: Ink.cinnabar))
                        .frame(height: 1.5)
                }

                ZStack(alignment: .top) {
                    PanelWebView(controller: controller)

                    if let error = controller.lastError {
                        errorBanner(error)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showToolbar {
                    toolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedHandle
                }
            }
            .background(Ink.paper)
            .overlay(alignment: .bottom) {
                if let toast = controller.toast {
                    InkToast(text: toast)
                        .padding(.bottom, showToolbar ? 92 : 58)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.toast)
            .animation(.easeInOut(duration: 0.2), value: showToolbar)
        }
        .privacyLock()
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            if let fresh = store.profile(with: currentProfile.id) {
                currentProfile = fresh
            }
            controller.load()
        }
        .sheet(isPresented: $showSwitcher) {
            ServerSwitcherSheet(currentId: currentProfile.id) { profile in
                switchTo(profile)
            }
        }
        .sheet(isPresented: $showQuick) {
            QuickPanelView(
                profile: currentProfile,
                username: store.credentials(for: currentProfile.id).username,
                password: store.password(for: currentProfile.id)
            )
        }
        .sheet(isPresented: $controller.showsSubscriptions) {
            SubscriptionSheet(links: controller.subscriptionLinks, codes: controller.subscriptionCodes)
        }
        .confirmationDialog("清除网页数据？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除并重新打开", role: .destructive) {
                controller.clearWebsiteData()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("会清掉所有面板的登录状态、Cookie 与缓存，之后需要重新登录。")
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Ink.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Ink.ink.opacity(0.06)))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentProfile.name)
                        .font(Ink.serif(15, .semibold))
                        .foregroundColor(Ink.ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundColor(Ink.inkFaint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Menu {
                    moreMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Ink.ink)
                        .frame(width: 34, height: 34)
                }

                Button {
                    showQuick = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Ink.indigo)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Ink.indigo.opacity(0.1)))
                }

                Button {
                    showSwitcher = true
                } label: {
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Ink.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Ink.ink.opacity(0.06)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Ink.ink.opacity(0.06))
                .frame(height: 0.5)
        }
        .background(Ink.paper.opacity(0.98))
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button {
            controller.reload()
        } label: {
            Label("重新加载", systemImage: "arrow.clockwise")
        }
        Button {
            controller.copyCurrentURL()
        } label: {
            Label("复制当前地址", systemImage: "doc.on.doc")
        }
        Button {
            controller.shareCurrentURL()
        } label: {
            Label("分享当前地址", systemImage: "square.and.arrow.up")
        }
        Button {
            controller.openInSafari()
        } label: {
            Label("在 Safari 打开", systemImage: "safari")
        }
        Divider()
        Button {
            controller.setUserAgent(controller.userAgentMode == .desktop ? .mobile : .desktop)
            store.updatePreferences(id: currentProfile.id, userAgent: controller.userAgentMode)
        } label: {
            Label(controller.userAgentMode == .desktop ? "切到手机版" : "切到电脑版", systemImage: "rectangle.on.rectangle")
        }
        if currentProfile.trustSelfSigned {
            Button {
                store.updatePreferences(id: currentProfile.id, trustSelfSigned: false)
                if let fresh = store.profile(with: currentProfile.id) { currentProfile = fresh }
                controller.showToast("已关闭自签证书信任，下次加载生效")
            } label: {
                Label("关闭自签证书信任", systemImage: "lock.open")
            }
        } else {
            Button {
                store.updatePreferences(id: currentProfile.id, trustSelfSigned: true)
                if let fresh = store.profile(with: currentProfile.id) { currentProfile = fresh }
                controller.showToast("已信任自签证书，正在重试")
                controller.reload()
            } label: {
                Label("信任自签证书", systemImage: "lock.shield")
            }
        }
        Divider()
        Button {
            confirmClear = true
        } label: {
            Label("清除缓存与 Cookie", systemImage: "trash")
        }
        Button {
            lock.lock()
        } label: {
            Label("立即上锁", systemImage: "lock")
        }
        Divider()
        Button(role: .destructive) {
            dismiss()
        } label: {
            Label("关闭面板", systemImage: "xmark")
        }
    }

    private var statusColor: Color {
        if controller.lastError != nil { return Ink.cinnabar }
        if controller.isLoading { return Ink.gold }
        return Ink.moss
    }

    private var statusText: String {
        if let _ = controller.lastError { return "连接异常" }
        if controller.isLoading { return "正在加载…" }
        if !controller.pageTitle.isEmpty { return controller.pageTitle }
        return currentProfile.hostAndPath
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Ink.ink.opacity(0.07))
                .frame(height: 0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    InkIconButton(systemName: "chevron.left", title: "后退") {
                        controller.goBack()
                    }
                    .opacity(controller.canGoBack ? 1 : 0.32)
                    .disabled(!controller.canGoBack)

                    InkIconButton(systemName: "chevron.right", title: "前进") {
                        controller.goForward()
                    }
                    .opacity(controller.canGoForward ? 1 : 0.32)
                    .disabled(!controller.canGoForward)

                    InkIconButton(
                        systemName: controller.isLoading ? "xmark" : "arrow.clockwise",
                        title: controller.isLoading ? "停止" : "刷新"
                    ) {
                        if controller.isLoading {
                            controller.stop()
                        } else {
                            controller.reload()
                        }
                    }

                    InkIconButton(systemName: "house", title: "首页") {
                        controller.goHome()
                    }

                    InkIconButton(
                        systemName: "desktopcomputer",
                        title: controller.userAgentMode == .desktop ? "电脑版" : "手机版",
                        isActive: controller.userAgentMode == .desktop,
                        tint: Ink.indigo
                    ) {
                        controller.toggleUserAgent()
                        store.updatePreferences(id: currentProfile.id, userAgent: controller.userAgentMode)
                    }

                    InkIconButton(
                        systemName: "person.crop.circle",
                        title: "填账号",
                        tint: Ink.cinnabar
                    ) {
                        controller.fillSavedLogin()
                    }

                    InkIconButton(systemName: "qrcode", title: "订阅") {
                        controller.extractSubscriptions()
                    }

                    InkIconButton(systemName: "doc.on.doc", title: "复制地址") {
                        controller.copyCurrentURL()
                    }

                    InkIconButton(systemName: "chevron.down", title: "收起") {
                        showToolbar = false
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
            .background(Ink.paper.opacity(0.98))
        }
    }

    private var collapsedHandle: some View {
        Button {
            showToolbar = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up")
                Text("工具栏")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(Ink.inkSoft)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Ink.paper)
                    .shadow(color: Ink.ink.opacity(0.12), radius: 6, x: 0, y: 2)
            )
        }
        .padding(.bottom, 6)
    }

    // MARK: - 错误提示

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Ink.cinnabar)
                    .font(.system(size: 13))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundColor(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    controller.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Ink.inkFaint)
                }
            }

            HStack(spacing: 10) {
                Button("重试") {
                    controller.reload()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Ink.indigo)

                if message.contains("证书") && !currentProfile.trustSelfSigned {
                    Button("信任自签证书并重试") {
                        store.updatePreferences(id: currentProfile.id, trustSelfSigned: true)
                        if let fresh = store.profile(with: currentProfile.id) {
                            currentProfile = fresh
                            controller.load(profile: fresh, username: store.credentials(for: fresh.id).username, password: store.password(for: fresh.id))
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Ink.cinnabar)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Ink.cinnabar.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Ink.ink.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    // MARK: - 切换服务器

    private func switchTo(_ profile: ServerProfile) {
        currentProfile = profile
        let credentials = store.credentials(for: profile.id)
        controller.load(profile: profile, username: credentials.username, password: credentials.password)
        store.moveToTop(id: profile.id)
    }
}
