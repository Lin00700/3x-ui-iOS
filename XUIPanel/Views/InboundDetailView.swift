import SwiftUI

/// 单个入站的详情：客户端、流量、分享链接与二维码。
struct InboundDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let inbound: InboundSummary
    let fallbackHost: String
    let panelURL: URL?

    @State private var preview: PreviewItem?
    @State private var copied: String?

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        infoCard
                        clientsSection

                        if inbound.clients.isEmpty {
                            Text("这个入站下没有可单独管理的客户端（例如 WireGuard / Dokodemo 这类入站）。")
                                .font(.system(size: 12))
                                .foregroundColor(Ink.inkFaint)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(inbound.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Ink.inkSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        copyAllLinks()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Ink.ink)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $preview) { item in
            QRPreviewSheet(text: item.text)
        }
        .privacyLock()
    }

    // MARK: 入站信息

    private var infoCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    InkTag(text: inbound.protocolLabel, tint: Ink.indigo)
                    Text(":\(inbound.port)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Ink.inkSoft)
                    Spacer()
                    InkTag(text: inbound.enabled ? "已启用" : "已停用", tint: inbound.enabled ? Ink.moss : Ink.inkFaint)
                }

                HStack(spacing: 16) {
                    infoItem("传输", inbound.network.uppercased())
                    infoItem("加密", inbound.security.uppercased())
                    infoItem("到期", PanelFormat.expiry(inbound.expiryTime))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("总流量")
                            .font(.system(size: 10.5))
                            .foregroundColor(Ink.inkFaint)
                        Spacer()
                        Text("\(PanelFormat.bytes(inbound.traffic)) / \(inbound.total > 0 ? PanelFormat.bytes(inbound.total) : "不限")")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Ink.inkSoft)
                    }
                    InkBar(value: inbound.trafficPercent, tint: Ink.indigo)
                }

                if let sni = inbound.tlsServerName {
                    Text("SNI \(sni)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                }
            }
        }
    }

    private func infoItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Ink.inkFaint)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 客户端

    private var clientsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("客户端")
                    .font(Ink.serif(15, .semibold))
                    .foregroundColor(Ink.ink)
                Text("\(inbound.clients.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Ink.inkFaint)
                Spacer()
            }
            .padding(.horizontal, 2)

            ForEach(inbound.clients) { client in
                clientCard(client)
            }
        }
    }

    private func clientCard(_ client: ClientSummary) -> some View {
        let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: fallbackHost)
        let subscription = ShareLinkBuilder.subscriptionURL(for: client, panelURL: panelURL)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(client.email.isEmpty ? "未命名客户端" : client.email)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(client.enabled ? Ink.ink : Ink.inkFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !client.enabled {
                    InkTag(text: "已停用", tint: Ink.inkFaint)
                }
                Text(PanelFormat.expiry(client.expiryTime))
                    .font(.system(size: 10))
                    .foregroundColor(Ink.inkFaint)
            }

            HStack(spacing: 8) {
                Text("↑ \(PanelFormat.bytes(client.up))  ↓ \(PanelFormat.bytes(client.down))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                if client.total > 0 {
                    Text("/ \(PanelFormat.bytes(client.total))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer()
            }

            if client.total > 0 {
                InkBar(value: client.trafficPercent, tint: Ink.moss, height: 3.5)
            }

            HStack(spacing: 8) {
                if let link = link {
                    actionChip(title: copied == link ? "已复制" : "复制链接", symbol: "link", active: copied == link) {
                        UIHelpers.copyToPasteboard(link)
                        copied = link
                    }
                    actionChip(title: "二维码", symbol: "qrcode", active: false) {
                        preview = PreviewItem(text: link)
                    }
                } else {
                    Text("此协议请到网页里复制链接")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if let subscription = subscription {
                    actionChip(title: "订阅", symbol: "dot.radiowaves.left.and.right", active: false) {
                        preview = PreviewItem(text: subscription)
                    }
                }
                Spacer()
            }
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
    }

    private func actionChip(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(active ? Ink.moss : Ink.indigo)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill((active ? Ink.moss : Ink.indigo).opacity(0.1)))
        }
        .buttonStyle(BorderlessButtonStyle())
    }

    private func copyAllLinks() {
        let links = inbound.clients.compactMap { client in
            ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: fallbackHost)
        }
        guard !links.isEmpty else {
            UIHelpers.copyToPasteboard(inbound.name)
            return
        }
        UIHelpers.copyToPasteboard(links.joined(separator: "\n"))
        copied = links.first
    }
}
