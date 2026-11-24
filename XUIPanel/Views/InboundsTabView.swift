import SwiftUI

/// 页签二：入站列表（卡片）、启停、流量、新建与删除。
struct InboundsTabView: View {
    @ObservedObject var session: PanelSession
    var onAdd: () -> Void
    var onWeb: () -> Void
    var onLogin: () -> Void

    @State private var selected: InboundSummary?
    @State private var confirmDelete: InboundSummary?
    @State private var keyword: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 10) {
                        headerCard
                        content
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
                .refreshable {
                    session.refresh()
                }
            }
            .navigationTitle("入站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            session.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                        }
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Ink.paper)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Ink.ink))
                        }
                    }
                    .foregroundColor(Ink.ink)
                }
            }
            .sheet(item: $selected) { inbound in
                InboundDetailView(session: session, inboundId: inbound.id, onWeb: onWeb)
            }
            .confirmationDialog(
                Text("删除「\((confirmDelete?.name) ?? "")」？"),
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmDelete
            ) { inbound in
                Button("删除入站", role: .destructive) {
                    session.deleteInbound(inbound) { _ in }
                    confirmDelete = nil
                }
                Button("取消", role: .cancel) {
                    confirmDelete = nil
                }
            } message: { inbound in
                Text("这个入站和它下面的 " + "\(inbound.clientCount)" + " 个客户端会一起从面板移除。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 顶部

    private var headerCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(Ink.inkFaint)
                    TextField("搜备注、端口或协议", text: $keyword)
                        .font(.system(size: 12.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.8))
                )

                Button {
                    onAdd()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("新建")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundColor(Ink.paper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Ink.ink))
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 6) {
                Text("\(session.inbounds.count) 个入站")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                Text("·")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                Text("\(enabledCount) 个启用")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.moss)
                Spacer(minLength: 0)
                if session.isWorking {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }
    }

    private var enabledCount: Int {
        var count = 0
        for inbound in session.inbounds where inbound.enabled {
            count += 1
        }
        return count
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if session.overview == nil && session.isLoading {
            PanelLoadingCard()
        } else if session.overview == nil && session.errorText != nil {
            PanelErrorCard(
                message: session.errorText ?? "",
                onRetry: { session.refresh() },
                onLogin: onLogin,
                onWeb: onWeb,
                retrying: session.isLoading
            )
        } else if filtered.isEmpty {
            InkCard {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(Ink.ink.opacity(0.35))
                    Text(keyword.isEmpty ? "还没有入站" : "没有匹配的入站")
                        .font(Ink.serif(14, .medium))
                        .foregroundColor(Ink.ink)
                    Text(keyword.isEmpty ? "点右上角 + 建一个，协议、端口、UUID 都能在这里配好。" : "换个关键词试试。")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkFaint)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        } else {
            ForEach(filtered) { inbound in
                inboundCard(inbound)
            }
        }
    }

    private var filtered: [InboundSummary] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return session.inbounds }
        return session.inbounds.filter { inbound in
            inbound.name.lowercased().contains(text)
                || String(inbound.port).contains(text)
                || inbound.protocolName.contains(text)
        }
    }

    private func inboundCard(_ inbound: InboundSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    InkTag(text: inbound.protocolLabel, tint: protocolTint(inbound.protocolName))
                    Text(inbound.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(inbound.enabled ? Ink.ink : Ink.inkFaint)
                        .lineLimit(1)
                    Text(":" + "\(inbound.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text("↑ " + PanelFormat.bytes(inbound.up) + "  ↓ " + PanelFormat.bytes(inbound.down))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                        .lineLimit(1)
                    if inbound.total > 0 {
                        Text("/ " + PanelFormat.bytes(inbound.total))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Ink.inkFaint)
                    }
                    Spacer(minLength: 0)
                    Text("\(inbound.clientCount) 客户端")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if inbound.total > 0 {
                    InkBar(value: inbound.trafficPercent, tint: Ink.indigo, height: 4)
                }

                HStack(spacing: 6) {
                    Text(inbound.network.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Ink.inkFaint)
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundColor(Ink.inkFaint)
                    Text(inbound.security.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(inbound.security == "reality" ? Ink.cinnabar : Ink.inkFaint)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Ink.ink.opacity(0.25))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selected = inbound
            }

            Toggle("", isOn: Binding(
                get: { inbound.enabled },
                set: { value in session.setEnabled(inbound, enabled: value) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Ink.moss))
            .disabled(session.isWorking)
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
        .opacity(inbound.enabled ? 1 : 0.7)
        .contextMenu {
            Button {
                selected = inbound
            } label: {
                Label("打开详情", systemImage: "chevron.right.circle")
            }
            Button {
                session.setEnabled(inbound, enabled: !inbound.enabled)
            } label: {
                Label(inbound.enabled ? "停用" : "启用", systemImage: inbound.enabled ? "pause.circle" : "play.circle")
            }
            Button {
                copyLinks(inbound)
            } label: {
                Label("复制全部链接", systemImage: "link")
            }
            Button {
                session.resetInboundTraffics(inbound)
            } label: {
                Label("清零这个入站的流量", systemImage: "arrow.counterclockwise")
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = inbound
            } label: {
                Label("删除入站", systemImage: "trash")
            }
        }
    }

    private func copyLinks(_ inbound: InboundSummary) {
        var links: [String] = []
        for client in inbound.clients {
            if let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: session.linkHost) {
                links.append(link)
            }
        }
        if links.isEmpty {
            session.showToast("这个入站没有可复制的链接")
            return
        }
        UIHelpers.copyToPasteboard(links.joined(separator: "\n"))
        session.showToast("已复制 \(links.count) 条链接")
    }

    private func protocolTint(_ name: String) -> Color {
        switch name {
        case "vless": return Ink.indigo
        case "vmess": return Ink.moss
        case "trojan": return Ink.cinnabar
        case "shadowsocks": return Ink.gold
        default: return Ink.inkSoft
        }
    }
}
