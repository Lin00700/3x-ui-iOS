import SwiftUI

/// 页签四：备份、维护、日志与「原版网页」入口。
struct ToolsTabView: View {
    @EnvironmentObject private var lock: LockManager

    @ObservedObject var session: PanelSession
    var onOpenWeb: () -> Void
    var onSwitchServer: () -> Void
    var onLogin: () -> Void

    @State private var logTarget: LogTarget?
    @State private var confirmRestart = false
    @State private var confirmReset = false
    @State private var confirmPanelRestart = false

    private struct LogTarget: Identifiable {
        let id = UUID()
        let xray: Bool
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        backupCard
                        maintenanceCard
                        logsCard
                        advancedCard
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("工具")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $logTarget) { target in
                LogViewerSheet(session: session, xray: target.xray)
            }
            .confirmationDialog("重启 Xray 服务？", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("重启 Xray", role: .destructive) {
                    session.restartXray()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("正在连接的客户端会断开几秒，服务随后自动恢复。")
            }
            .confirmationDialog("重置全部流量？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("全部清零", role: .destructive) {
                    session.resetAllTraffics()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("所有入站与客户端的已用流量都会归零，这个操作没法撤销。")
            }
            .confirmationDialog("重启面板？", isPresented: $confirmPanelRestart, titleVisibility: .visible) {
                Button("重启面板", role: .destructive) {
                    session.restartPanel()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("面板会短暂离线，网页和这个 App 都会断开一会儿。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 备份

    private var backupCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "备份与数据", trailing: "x-ui.db 里是全部账号")

                QuickActionButton(
                    title: session.isWorking ? "正在准备…" : "下载数据库备份",
                    symbol: "externaldrive.badge.timemachine",
                    tint: Ink.indigo,
                    filled: true,
                    loading: session.isWorking
                ) {
                    session.downloadDatabase()
                }

                HStack(spacing: 10) {
                    QuickActionButton(title: "复制面板地址", symbol: "doc.on.doc", tint: Ink.inkSoft) {
                        UIHelpers.copyToPasteboard(session.profile.url?.absoluteString ?? "")
                        session.showToast("面板地址已复制")
                    }
                    QuickActionButton(title: "复制订阅地址", symbol: "dot.radiowaves.left.and.right", tint: Ink.inkSoft) {
                        copyFirstSubscription()
                    }
                }
            }
        }
    }

    // MARK: - 维护

    private var maintenanceCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "维护", trailing: "带确认，点错不会直接执行")

                HStack(spacing: 10) {
                    QuickActionButton(title: "重启 Xray", symbol: "bolt.horizontal.circle", tint: Ink.cinnabar) {
                        confirmRestart = true
                    }
                    QuickActionButton(title: "重置全部流量", symbol: "arrow.counterclockwise", tint: Ink.cinnabar) {
                        confirmReset = true
                    }
                }

                QuickActionButton(title: "重启面板", symbol: "power", tint: Ink.inkSoft) {
                    confirmPanelRestart = true
                }
            }
        }
    }

    // MARK: - 日志

    private var logsCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "日志", trailing: "最近 200 行")

                HStack(spacing: 10) {
                    QuickActionButton(title: "面板日志", symbol: "doc.text.magnifyingglass", tint: Ink.indigo) {
                        logTarget = LogTarget(xray: false)
                    }
                    QuickActionButton(title: "Xray 日志", symbol: "waveform.path.ecg", tint: Ink.moss) {
                        logTarget = LogTarget(xray: true)
                    }
                }

                Text("排查连不上、证书错误、流量异常时，先看 Xray 日志里的报错行。")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 高级

    private var advancedCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "高级", trailing: "原生 UI 没覆盖的设置都在网页里")

                QuickActionButton(title: "打开原版网页面板", symbol: "safari", tint: Ink.ink, filled: true) {
                    onOpenWeb()
                }

                HStack(spacing: 10) {
                    QuickActionButton(title: "切换服务器", symbol: "server.rack", tint: Ink.inkSoft) {
                        onSwitchServer()
                    }
                    QuickActionButton(title: "登录 / 换账号", symbol: "person.badge.key", tint: Ink.inkSoft) {
                        onLogin()
                    }
                }

                Button {
                    lock.lock()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 11, weight: .medium))
                        Text("立即上锁")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Ink.inkSoft)
                }
                .buttonStyle(PlainButtonStyle())

                Text("自签证书、订阅设置、外部流量、节点管理这些偏冷门的项，仍然建议在网页里改。")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyFirstSubscription() {
        if let settings = session.panelSettings, !settings.subURI.isEmpty {
            UIHelpers.copyToPasteboard(settings.subURI)
            session.showToast("订阅根地址已复制")
            return
        }
        for node in session.nodes {
            if let sub = node.subscription {
                UIHelpers.copyToPasteboard(sub)
                session.showToast("订阅地址已复制")
                return
            }
        }
        session.showToast("面板里还没有可用的订阅地址")
    }
}
