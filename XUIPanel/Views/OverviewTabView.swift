import SwiftUI

/// 页签一：服务器概况、资源占用、累计流量、在线客户端与快捷动作。
struct OverviewTabView: View {
    @ObservedObject var session: PanelSession
    var onOpenWeb: () -> Void
    var onSwitchServer: () -> Void
    var onLogin: () -> Void
    var onAddInbound: () -> Void

    @State private var confirmRestart = false

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        content
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
                .refreshable {
                    session.refresh()
                }
            }
            .navigationTitle("概览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            session.autoRefresh.toggle()
                        } label: {
                            Image(systemName: session.autoRefresh ? "arrow.triangle.2.circlepath" : "pause.circle")
                                .font(.system(size: 15))
                        }
                        Button {
                            session.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .foregroundColor(Ink.ink)
                }
            }
            .confirmationDialog("重启 Xray 服务？", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("重启", role: .destructive) {
                    session.restartXray()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("正在连接的客户端会断开几秒，服务随后自动恢复。")
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        if let overview = session.overview {
            heroCard(overview)
            metricsRow(overview)
            trafficCard(overview)
            if !overview.onlineEmails.isEmpty {
                onlineCard(overview)
            }
            quickActions
            footNote(overview)
        } else if session.isLoading {
            PanelLoadingCard()
        } else if let error = session.errorText {
            PanelErrorCard(
                message: error,
                onRetry: { session.refresh() },
                onLogin: onLogin,
                onWeb: onOpenWeb,
                retrying: session.isLoading
            )
        } else {
            PanelLoadingCard(title: "准备中", note: "正在连接这台面板")
        }
    }

    // MARK: - 首卡

    private func heroCard(_ overview: PanelOverview) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    InkSeal(text: session.profile.sealCharacter, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.profile.name)
                            .font(Ink.serif(16, .semibold))
                            .foregroundColor(Ink.ink)
                            .lineLimit(1)
                        Text(onlineSummary(overview))
                            .font(.system(size: 11))
                            .foregroundColor(Ink.inkFaint)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(overview.isXrayRunning ? Ink.moss : Ink.cinnabar)
                                .frame(width: 6, height: 6)
                            Text(overview.isXrayRunning ? "Xray 运行中" : "Xray " + overview.xrayState)
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

                HStack(spacing: 14) {
                    StatItem(title: "运行时长", value: PanelFormat.uptime(overview.uptimeSeconds))
                    StatItem(title: "在线", value: "\(overview.onlineCount)")
                    StatItem(title: "入站", value: "\(session.inbounds.count)")
                }

                if let ip = publicIPText(overview) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.system(size: 9.5))
                            .foregroundColor(Ink.inkFaint)
                        Text(ip)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Ink.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 6) {
                    Text(session.autoRefresh ? "自动刷新：开（12 秒）" : "自动刷新：关")
                        .font(.system(size: 9.5))
                        .foregroundColor(Ink.inkFaint)
                    Spacer(minLength: 0)
                    Text(updatedText(overview))
                        .font(.system(size: 9.5))
                        .foregroundColor(Ink.inkFaint)
                }
            }
        }
    }

    // MARK: - 指标

    private func metricsRow(_ overview: PanelOverview) -> some View {
        HStack(spacing: 10) {
            MetricTile(
                title: "CPU",
                value: PanelFormat.cpu(overview.cpuPercent),
                ratio: min(max((overview.cpuPercent ?? 0) / 100, 0), 1),
                tint: Ink.indigo
            )
            MetricTile(
                title: "内存",
                value: PanelFormat.percent(overview.memPercent),
                ratio: min(max(overview.memPercent ?? 0, 0), 1),
                tint: Ink.moss,
                note: PanelFormat.bytes(overview.memUsed) + " / " + PanelFormat.bytes(overview.memTotal)
            )
            MetricTile(
                title: "磁盘",
                value: PanelFormat.percent(overview.diskPercent),
                ratio: min(max(overview.diskPercent ?? 0, 0), 1),
                tint: Ink.gold,
                note: PanelFormat.bytes(overview.diskUsed) + " / " + PanelFormat.bytes(overview.diskTotal)
            )
        }
    }

    // MARK: - 流量

    private func trafficCard(_ overview: PanelOverview) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "流量", trailing: "自 Xray 启动起累计")

                HStack(spacing: 10) {
                    trafficTile(title: "上行", value: PanelFormat.bytes(overview.netUp), symbol: "arrow.up", tint: Ink.indigo)
                    trafficTile(title: "下行", value: PanelFormat.bytes(overview.netDown), symbol: "arrow.down", tint: Ink.moss)
                }

                if overview.tcpCount != nil || overview.udpCount != nil {
                    HStack(spacing: 14) {
                        StatItem(
                            title: "TCP 连接",
                            value: overview.tcpCount == nil ? "—" : String(format: "%.0f", overview.tcpCount ?? 0)
                        )
                        StatItem(
                            title: "UDP 连接",
                            value: overview.udpCount == nil ? "—" : String(format: "%.0f", overview.udpCount ?? 0)
                        )
                        StatItem(title: "客户端总数", value: "\(session.totalClients)")
                    }
                } else {
                    StatItem(title: "客户端总数", value: "\(session.totalClients)")
                }
            }
        }
    }

    private func trafficTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundColor(Ink.inkFaint)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Ink.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Ink.ink.opacity(0.035))
        )
    }

    // MARK: - 在线

    private func onlineCard(_ overview: PanelOverview) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "在线客户端", count: overview.onlineEmails.count)

                let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(overview.onlineEmails.indices, id: \.self) { index in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Ink.moss)
                                .frame(width: 4, height: 4)
                            Text(overview.onlineEmails[index])
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Ink.inkSoft)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Ink.moss.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    // MARK: - 快捷动作

    private var quickActions: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "快捷动作")

            HStack(spacing: 10) {
                QuickActionButton(
                    title: session.isLoading ? "刷新中" : "刷新",
                    symbol: "arrow.clockwise",
                    tint: Ink.indigo,
                    loading: session.isLoading
                ) {
                    session.refresh()
                }
                QuickActionButton(
                    title: "重启 Xray",
                    symbol: "bolt.horizontal.circle",
                    tint: Ink.cinnabar,
                    loading: session.isWorking
                ) {
                    confirmRestart = true
                }
            }

            HStack(spacing: 10) {
                QuickActionButton(title: "切换服务器", symbol: "server.rack", tint: Ink.inkSoft) {
                    onSwitchServer()
                }
                QuickActionButton(title: "新建入站", symbol: "plus.circle", tint: Ink.moss, filled: true) {
                    onAddInbound()
                }
            }
        }
    }

    private func footNote(_ overview: PanelOverview) -> some View {
        Text("数据来自面板 /server/status 与 /inbounds/list；重活（证书、路由、数据库设置）可以点右上角「原版网页」处理。")
            .font(.system(size: 10))
            .foregroundColor(Ink.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - 小工具

    private func onlineSummary(_ overview: PanelOverview) -> String {
        if overview.onlineCount == 0 {
            return "暂无客户端在线"
        }
        return String(overview.onlineCount) + " 个客户端在线"
    }

    private func publicIPText(_ overview: PanelOverview) -> String? {
        if !overview.publicIPv4.isEmpty {
            return overview.publicIPv4
        }
        if !overview.publicIPv6.isEmpty {
            return overview.publicIPv6
        }
        return nil
    }

    private func updatedText(_ overview: PanelOverview) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "更新于 " + formatter.string(from: overview.fetchedAt)
    }
}
