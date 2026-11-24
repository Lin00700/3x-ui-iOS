import SwiftUI

/// 页签三：把面板里所有客户端整理成可一键复制、出二维码、拿订阅地址的清单。
struct ShareTabView: View {
    @ObservedObject var session: PanelSession
    var onWeb: () -> Void
    var onLogin: () -> Void

    @State private var preview: QRItem?
    @State private var keyword: String = ""
    @State private var copiedId: String?

    private struct QRItem: Identifiable {
        let id = UUID()
        let text: String
        let title: String
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        subscriptionCard
                        searchField
                        nodeList
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
                .refreshable {
                    session.refresh()
                }
            }
            .navigationTitle("订阅与分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        copyAll()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Ink.ink)
                    }
                    .disabled(session.nodes.isEmpty)
                }
            }
            .sheet(item: $preview) { item in
                QRPreviewSheet(text: item.text)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 订阅

    private var subscriptionCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Ink.indigo)
                    Text("订阅")
                        .font(Ink.serif(15, .semibold))
                        .foregroundColor(Ink.ink)
                    Spacer(minLength: 0)
                    if let settings = session.panelSettings {
                        InkTag(
                            text: settings.subEnable ? "面板已开启" : "面板未开启",
                            tint: settings.subEnable ? Ink.moss : Ink.inkFaint
                        )
                    }
                }

                if let settings = session.panelSettings {
                    HStack(spacing: 14) {
                        StatItem(title: "订阅端口", value: "\(settings.subPort)")
                        StatItem(title: "订阅路径", value: settings.subPath)
                    }
                } else {
                    Text("还没读到面板的订阅设置，先用默认的 /sub/ 路径。")
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkFaint)
                }

                Text("每个客户端都有自己的订阅地址（/sub/<subId>）；在客户端 App 里更新订阅，节点会跟着面板变。")
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    QuickActionButton(title: "复制全部链接", symbol: "doc.on.doc", tint: Ink.indigo, filled: true) {
                        copyAll()
                    }
                    QuickActionButton(title: "分享全部", symbol: "square.and.arrow.up", tint: Ink.inkSoft) {
                        shareAll()
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Ink.inkFaint)
            TextField("搜客户端、协议或备注", text: $keyword)
                .font(.system(size: 12.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Ink.inkFaint)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
    }

    // MARK: - 节点列表

    @ViewBuilder
    private var nodeList: some View {
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
        } else if session.nodes.isEmpty {
            PanelHint(text: "面板里还没有客户端。到「入站」页建一个入站，客户端会带着链接出现在这里。")
        } else {
            ForEach(groups) { group in
                groupSection(group)
            }
        }
    }

    private struct NodeGroup: Identifiable {
        var inbound: InboundSummary
        var nodes: [ShareNode]
        var id: Int { inbound.id }
    }

    private var groups: [NodeGroup] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [NodeGroup] = []
        for inbound in session.inbounds {
            var nodes: [ShareNode] = []
            for client in inbound.clients {
                let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: session.linkHost)
                let sub = ShareLinkBuilder.subscriptionURL(
                    subId: client.subId,
                    settings: session.panelSettings,
                    panelURL: session.profile.url
                )
                let node = ShareNode(inbound: inbound, client: client, link: link, subscription: sub)
                if text.isEmpty {
                    nodes.append(node)
                } else if client.email.lowercased().contains(text)
                    || inbound.name.lowercased().contains(text)
                    || inbound.protocolName.contains(text) {
                    nodes.append(node)
                }
            }
            if !nodes.isEmpty {
                result.append(NodeGroup(inbound: inbound, nodes: nodes))
            }
        }
        return result
    }

    private func groupSection(_ group: NodeGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                InkTag(text: group.inbound.protocolLabel, tint: protocolTint(group.inbound.protocolName))
                Text(group.inbound.name)
                    .font(Ink.serif(13.5, .semibold))
                    .foregroundColor(Ink.ink)
                    .lineLimit(1)
                Text(":" + "\(group.inbound.port)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                Spacer(minLength: 0)
                Text("\(group.nodes.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Ink.inkFaint)
            }
            .padding(.horizontal, 2)

            ForEach(group.nodes) { node in
                nodeCard(node)
            }
        }
        .padding(.top, 2)
    }

    private func nodeCard(_ node: ShareNode) -> some View {
        let copied = copiedId == node.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(node.client.email.isEmpty ? "未命名客户端" : node.client.email)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(node.client.enabled ? Ink.ink : Ink.inkFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !node.client.enabled {
                    InkTag(text: "已停用", tint: Ink.inkFaint)
                }
                Text(PanelFormat.bytes(node.client.traffic))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
            }

            HStack(spacing: 8) {
                if node.link != nil {
                    ChipButton(title: copied ? "已复制" : "链接", symbol: "link", active: copied) {
                        copy(node)
                    }
                    ChipButton(title: "二维码", symbol: "qrcode") {
                        if let link = node.link {
                            preview = QRItem(text: link, title: node.client.email)
                        }
                    }
                } else {
                    Text("此协议请到网页复制链接")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if node.subscription != nil {
                    ChipButton(title: "订阅", symbol: "dot.radiowaves.left.and.right") {
                        if let sub = node.subscription {
                            preview = QRItem(text: sub, title: node.client.email + " 订阅")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Ink.ink.opacity(0.06), lineWidth: 1)
        )
        .opacity(node.client.enabled ? 1 : 0.7)
    }

    // MARK: - 动作

    private func copy(_ node: ShareNode) {
        guard let link = node.link else { return }
        UIHelpers.copyToPasteboard(link)
        copiedId = node.id
        session.showToast("链接已复制")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedId == node.id {
                copiedId = nil
            }
        }
    }

    private func copyAll() {
        let all = session.nodes.compactMap { $0.link }
        guard !all.isEmpty else {
            session.showToast("没有可复制的链接")
            return
        }
        UIHelpers.copyToPasteboard(all.joined(separator: "\n"))
        session.showToast("已复制 \(all.count) 条链接")
    }

    private func shareAll() {
        let all = session.nodes.compactMap { $0.link }
        guard !all.isEmpty else {
            session.showToast("没有可分享的链接")
            return
        }
        UIHelpers.share(items: all)
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
