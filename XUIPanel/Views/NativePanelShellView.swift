import SwiftUI

enum NativeTab: String, CaseIterable, Identifiable {
    case overview
    case inbounds
    case share
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .inbounds: return "入站"
        case .share: return "订阅"
        case .tools: return "工具"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge"
        case .inbounds: return "list.bullet.rectangle"
        case .share: return "qrcode"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

/// 点开服务器后的默认界面：全套原生 App UI，四个页签 + 随时可切原版网页。
struct NativePanelShellView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var lock: LockManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session: PanelSession
    @State private var tab: NativeTab = .overview
    @State private var showWeb = false
    @State private var showSwitcher = false
    @State private var showAddInbound = false
    @State private var showLogin = false

    init(profile: ServerProfile, username: String, password: String) {
        _session = StateObject(wrappedValue: PanelSession(profile: profile, username: username, password: password))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar

                TabView(selection: $tab) {
                    OverviewTabView(
                        session: session,
                        onOpenWeb: { showWeb = true },
                        onSwitchServer: { showSwitcher = true },
                        onLogin: { showLogin = true },
                        onAddInbound: { showAddInbound = true }
                    )
                    .tabItem {
                        Label(NativeTab.overview.title, systemImage: NativeTab.overview.symbol)
                    }
                    .tag(NativeTab.overview)

                    InboundsTabView(
                        session: session,
                        onAdd: { showAddInbound = true },
                        onWeb: { showWeb = true },
                        onLogin: { showLogin = true }
                    )
                    .tabItem {
                        Label(NativeTab.inbounds.title, systemImage: NativeTab.inbounds.symbol)
                    }
                    .tag(NativeTab.inbounds)

                    ShareTabView(
                        session: session,
                        onWeb: { showWeb = true },
                        onLogin: { showLogin = true }
                    )
                    .tabItem {
                        Label(NativeTab.share.title, systemImage: NativeTab.share.symbol)
                    }
                    .tag(NativeTab.share)

                    ToolsTabView(
                        session: session,
                        onOpenWeb: { showWeb = true },
                        onSwitchServer: { showSwitcher = true },
                        onLogin: { showLogin = true }
                    )
                    .tabItem {
                        Label(NativeTab.tools.title, systemImage: NativeTab.tools.symbol)
                    }
                    .tag(NativeTab.tools)
                }
                .accentColor(Ink.cinnabar)
            }

            if let toast = session.toast {
                InkToast(text: toast)
                    .padding(.bottom, 84)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .background(PaperBackground())
        .privacyLock()
        .onAppear {
            session.onSaveCredentials = { id, username, password in
                store.saveCredentials(id: id, username: username, password: password)
            }
            session.start()
        }
        .onChange(of: session.needsLogin) { needsLogin in
            if needsLogin && !session.hasCredentials {
                showLogin = true
            }
        }
        .fullScreenCover(isPresented: $showWeb, onDismiss: {
            session.reseedWebCookiesAndRefresh()
        }) {
            PanelScreen(
                profile: session.profile,
                username: store.credentials(for: session.profile.id).username,
                password: store.password(for: session.profile.id)
            )
        }
        .sheet(isPresented: $showSwitcher) {
            ServerSwitcherSheet(currentId: session.profile.id) { profile in
                let credentials = store.credentials(for: profile.id)
                session.switchProfile(profile, username: credentials.username, password: credentials.password)
                store.moveToTop(id: profile.id)
            }
        }
        .sheet(isPresented: $showAddInbound) {
            AddInboundSheet(session: session)
        }
        .sheet(isPresented: $showLogin) {
            ServerLoginSheet(
                session: session,
                initialUsername: store.credentials(for: session.profile.id).username
            )
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                InkSeal(text: session.profile.sealCharacter, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.profile.name)
                        .font(Ink.serif(16, .semibold))
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

                Spacer(minLength: 4)

                Button {
                    showWeb = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 11, weight: .medium))
                        Text("原版网页")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(Ink.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Ink.ink))
                }
                .buttonStyle(PlainButtonStyle())

                Menu {
                    moreMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Ink.ink)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Ink.paper.opacity(0.97))

            Rectangle()
                .fill(Ink.ink.opacity(0.07))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        Button {
            session.refresh()
        } label: {
            Label("刷新数据", systemImage: "arrow.clockwise")
        }
        Button {
            showSwitcher = true
        } label: {
            Label("切换服务器", systemImage: "server.rack")
        }
        Button {
            showLogin = true
        } label: {
            Label("登录 / 换账号", systemImage: "person.badge.key")
        }
        Button {
            UIHelpers.copyToPasteboard(session.profile.url?.absoluteString ?? "")
            session.showToast("面板地址已复制")
        } label: {
            Label("复制面板地址", systemImage: "doc.on.doc")
        }
        Divider()
        Button {
            lock.lock()
        } label: {
            Label("立即上锁", systemImage: "lock")
        }
        Button {
            dismiss()
        } label: {
            Label("关闭面板", systemImage: "xmark")
        }
    }

    private var statusColor: Color {
        if session.needsLogin { return Ink.cinnabar }
        if session.errorText != nil { return Ink.cinnabar }
        if session.isLoading { return Ink.gold }
        if let overview = session.overview, !overview.isXrayRunning { return Ink.gold }
        return Ink.moss
    }

    private var statusText: String {
        if session.needsLogin { return "需要登录" }
        if session.isLoading { return "正在加载…" }
        if session.errorText != nil { return "连接异常" }
        if let overview = session.overview {
            let state = overview.isXrayRunning ? "Xray 运行中" : "Xray " + overview.xrayState
            return state + " · \(overview.onlineCount) 在线"
        }
        return session.profile.hostAndPath
    }
}
