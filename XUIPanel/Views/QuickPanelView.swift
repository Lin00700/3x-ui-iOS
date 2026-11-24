import SwiftUI

// MARK: - 模型

struct InboundToggleRequest: Identifiable {
    let id = UUID()
    let inbound: InboundSummary
    let enabled: Bool
}

final class QuickPanelModel: ObservableObject {
    let profile: ServerProfile

    @Published var overview: PanelOverview?
    @Published var isLoading = false
    @Published var error: String?
    @Published var pendingToggle: InboundToggleRequest?
    @Published var isToggling = false
    @Published var isBackingUp = false
    @Published var toast: String?

    private let username: String
    private let password: String
    private var client: PanelAPIClient?
    private var started = false
    private var toastWorkItem: DispatchWorkItem?

    init(profile: ServerProfile, username: String, password: String) {
        self.profile = profile
        self.username = username
        self.password = password
    }

    var linkHost: String {
        if let ip = overview?.publicIPv4, !ip.isEmpty {
            return ip
        }
        if let ip = overview?.publicIPv6, !ip.isEmpty {
            return ip
        }
        return profile.url?.host ?? ""
    }

    var couldUseSavedLogin: Bool {
        !username.isEmpty || !password.isEmpty
    }

    // MARK: 加载

    func start() {
        guard !started else {
            refresh()
            return
        }
        started = true

        guard let url = profile.url else {
            error = "服务器地址无效"
            return
        }

        isLoading = true
        WebCookieReader.seedCookies(for: url) { [weak self] in
            guard let self = self else { return }
            guard let client = PanelAPIClient.make(profile: self.profile, username: self.username, password: self.password) else {
                self.isLoading = false
                self.error = "地址无效，无法定位面板 API"
                return
            }
            self.client = client
            self.refresh()
        }
    }

    func refresh() {
        guard let client = client else {
            started = false
            start()
            return
        }
        isLoading = true
        error = nil
        client.fetchOverview { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let overview):
                    self.overview = overview
                case .failure(let failure):
                    self.error = failure.localizedDescription
                }
            }
        }
    }

    // MARK: 启停

    func requestToggle(_ inbound: InboundSummary) {
        pendingToggle = InboundToggleRequest(inbound: inbound, enabled: !inbound.enabled)
    }

    func performToggle() {
        guard let request = pendingToggle, let client = client else {
            pendingToggle = nil
            return
        }
        pendingToggle = nil
        isToggling = true
        client.setInbound(request.inbound, enabled: request.enabled) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isToggling = false
                switch result {
                case .success:
                    self.showToast(request.enabled ? "已启用 \(request.inbound.name)" : "已停用 \(request.inbound.name)")
                    self.refresh()
                case .failure(let error):
                    self.showToast("操作失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: 备份

    func backupDatabase() {
        guard let client = client else { return }
        isBackingUp = true
        client.downloadDatabase { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBackingUp = false
                switch result {
                case .success(let url):
                    self.showToast("数据库已下载")
                    UIHelpers.share(items: [url])
                case .failure(let error):
                    self.showToast("备份失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: 提示

    func showToast(_ text: String) {
        toast = text
        toastWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.toast = nil
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item)
    }
}

// MARK: - 视图

/// 原生快捷概览：不用挤在网页表格里，直接看状态、入站、流量与备份。
struct QuickPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: QuickPanelModel
    @State private var selectedInbound: InboundSummary?

    init(profile: ServerProfile, username: String, password: String) {
        _model = StateObject(wrappedValue: QuickPanelModel(profile: profile, username: username, password: password))
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let overview = model.overview {
                            statusCard(overview)
                            inboundsSection(overview)
                            actionRow
                        } else if model.isLoading {
                            loadingCard
                        } else if let error = model.error {
                            errorCard(error)
                        } else {
                            loadingCard
                        }

                        if let error = model.error, model.overview != nil {
                            inlineError(error)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    model.refresh()
                }

                if let toast = model.toast {
                    VStack {
                        Spacer()
                        InkToast(text: toast)
                            .padding(.bottom, 26)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .navigationTitle("快捷概览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Ink.inkSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Ink.ink)
                    }
                    .disabled(model.isLoading)
                }
            }
            .confirmationDialog(
                Text(toggleTitle),
                isPresented: Binding(
                    get: { model.pendingToggle != nil },
                    set: { if !$0 { model.pendingToggle = nil } }
                ),
                titleVisibility: .visible,
                presenting: model.pendingToggle
            ) { request in
                if request.enabled {
                    Button("启用") { model.performToggle() }
                } else {
                    Button("停用", role: .destructive) { model.performToggle() }
                }
                Button("取消", role: .cancel) {
                    model.pendingToggle = nil
                }
            } message: { request in
                Text(request.enabled
                     ? "启用后 \(request.inbound.name) 会立即接受连接。"
                     : "停用后 \(request.inbound.name) 上的客户端会立刻断开。")
            }
            .sheet(item: $selectedInbound) { inbound in
                InboundDetailView(inbound: inbound, fallbackHost: model.linkHost, panelURL: model.profile.url)
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
        .onAppear {
            model.start()
        }
    }

    private var toggleTitle: String {
        guard let request = model.pendingToggle else { return "" }
        return request.enabled ? "启用这个入站？" : "停用这个入站？"
    }

    // MARK: 状态卡

    private func statusCard(_ overview: PanelOverview) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    InkSeal(text: "概", size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.profile.name)
                            .font(Ink.serif(16, .semibold))
                            .foregroundColor(Ink.ink)
                            .lineLimit(1)
                        Text(overview.onlineEmails.isEmpty ? "暂无在线客户端" : "\(overview.onlineCount) 个客户端在线")
                            .font(.system(size: 11))
                            .foregroundColor(Ink.inkFaint)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(overview.isXrayRunning ? Ink.moss : Ink.cinnabar)
                                .frame(width: 6, height: 6)
                            Text(overview.isXrayRunning ? "Xray 运行中" : "Xray \(overview.xrayState)")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(overview.isXrayRunning ? Ink.moss : Ink.cinnabar)
                        }
                        if !overview.xrayVersion.isEmpty {
                            Text(overview.xrayVersion)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(Ink.inkFaint)
                        }
                    }
                }

                HStack(spacing: 10) {
                    metricTile(title: "CPU", value: PanelFormat.cpu(overview.cpuPercent), ratio: (overview.cpuPercent ?? 0) / 100, tint: Ink.indigo)
                    metricTile(title: "内存", value: PanelFormat.percent(overview.memPercent), ratio: overview.memPercent ?? 0, tint: Ink.moss)
                    metricTile(title: "磁盘", value: PanelFormat.percent(overview.diskPercent), ratio: overview.diskPercent ?? 0, tint: Ink.gold)
                }

                HStack(spacing: 14) {
                    smallInfo(title: "运行", value: PanelFormat.uptime(overview.uptimeSeconds))
                    smallInfo(title: "入站", value: "\(overview.inbounds.count)")
                    smallInfo(title: "内存", value: "\(PanelFormat.bytes(overview.memUsed)) / \(PanelFormat.bytes(overview.memTotal))")
                }

                Text("更新于 \(timeString(overview.fetchedAt))")
                    .font(.system(size: 9.5))
                    .foregroundColor(Ink.inkFaint)
            }
        }
    }

    private func metricTile(title: String, value: String, ratio: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Ink.inkFaint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Ink.ink)
            InkBar(value: ratio, tint: tint, height: 4)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Ink.ink.opacity(0.035))
        )
    }

    private func smallInfo(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Ink.inkFaint)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Ink.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 入站

    private func inboundsSection(_ overview: PanelOverview) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("入站")
                    .font(Ink.serif(15, .semibold))
                    .foregroundColor(Ink.ink)
                Text("\(overview.inbounds.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Ink.inkFaint)
                Spacer()
                Text("点开看客户端")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
            }
            .padding(.horizontal, 2)

            if overview.inbounds.isEmpty {
                Text("这台面板还没有入站。")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.inkFaint)
                    .padding(.vertical, 10)
            }

            ForEach(overview.inbounds) { inbound in
                inboundCard(inbound)
            }
        }
    }

    private func inboundCard(_ inbound: InboundSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                InkTag(text: inbound.protocolLabel, tint: protocolTint(inbound.protocolName))
                Text(inbound.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Ink.ink)
                    .lineLimit(1)
                Text(":\(inbound.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                Spacer(minLength: 4)
                Button {
                    model.requestToggle(inbound)
                } label: {
                    Text(inbound.enabled ? "已启用" : "已停用")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(inbound.enabled ? Ink.moss : Ink.inkFaint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill((inbound.enabled ? Ink.moss : Ink.inkFaint).opacity(0.12))
                        )
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(model.isToggling)
            }

            HStack(spacing: 8) {
                Text("↑ \(PanelFormat.bytes(inbound.up))  ↓ \(PanelFormat.bytes(inbound.down))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                if inbound.total > 0 {
                    Text("/ \(PanelFormat.bytes(inbound.total))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer()
                Text("\(inbound.clientCount) 客户端")
                    .font(.system(size: 10))
                    .foregroundColor(Ink.inkFaint)
            }

            InkBar(value: inbound.trafficPercent, tint: Ink.indigo, height: 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Ink.ink.opacity(0.06), lineWidth: 1)
        )
        .opacity(inbound.enabled ? 1 : 0.62)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedInbound = inbound
        }
    }

    private func protocolTint(_ protocolName: String) -> Color {
        switch protocolName {
        case "vless": return Ink.indigo
        case "vmess": return Ink.moss
        case "trojan": return Ink.cinnabar
        case "shadowsocks": return Ink.gold
        case "wireguard": return Ink.inkSoft
        default: return Ink.inkSoft
        }
    }

    // MARK: 底部操作

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                model.backupDatabase()
            } label: {
                HStack(spacing: 6) {
                    if model.isBackingUp {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "externaldrive.badge.timemachine")
                    }
                    Text("备份数据库")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(Ink.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.ink))
            }
            .disabled(model.isBackingUp)

            Button {
                UIHelpers.copyToPasteboard(model.profile.url?.absoluteString ?? "")
                model.showToast("面板地址已复制")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("复制地址")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(Ink.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.ink.opacity(0.07)))
            }
        }
        .padding(.top, 4)
    }

    // MARK: 状态页

    private var loadingCard: some View {
        InkCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在读取面板数据")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Ink.ink)
                    Text("用的是网页同一套登录状态")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer()
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Ink.cinnabar)
                    Text("读不到面板数据")
                        .font(Ink.serif(15, .semibold))
                        .foregroundColor(Ink.ink)
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.couldUseSavedLogin {
                    Text("这台服务器没有保存账号密码。可以先在网页面板登录一次，或到服务器设置里补上账号密码后回来。")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.refresh()
                } label: {
                    Text("重试")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Ink.indigo)
                }
            }
        }
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(Ink.cinnabar)
            .padding(.horizontal, 4)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
