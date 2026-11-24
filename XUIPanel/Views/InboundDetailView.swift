import SwiftUI

/// 单个入站的原生详情：改备注 / 端口 / 启停、管客户端、复制链接与二维码、删除入站。
struct InboundDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: PanelSession
    var inboundId: Int
    var onWeb: () -> Void

    @State private var remark: String = ""
    @State private var portText: String = ""
    @State private var enabled: Bool = true
    @State private var didLoad = false
    @State private var preview: QRItem?
    @State private var confirmInboundDelete = false
    @State private var pendingClientDelete: ClientSummary?
    @State private var showAddClient = false
    @State private var copiedId: String?

    private struct QRItem: Identifiable {
        let id = UUID()
        let text: String
    }

    private var inbound: InboundSummary? {
        session.inbound(withId: inboundId)
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                if let inbound = inbound {
                    ScrollView {
                        VStack(spacing: 14) {
                            infoCard(inbound)
                            editCard(inbound)
                            clientsSection(inbound)
                            dangerCard(inbound)
                        }
                        .padding(16)
                        .padding(.bottom, 20)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(Ink.ink.opacity(0.3))
                        Text("这个入站已经不在面板里了")
                            .font(Ink.serif(15, .medium))
                            .foregroundColor(Ink.ink)
                        Button("关闭") {
                            dismiss()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Ink.indigo)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle(inbound?.name ?? "入站详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(Ink.inkSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            copyAllLinks()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Button {
                            openWebPanel()
                        } label: {
                            Image(systemName: "safari")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(Ink.ink)
                }
            }
            .sheet(item: $preview) { item in
                QRPreviewSheet(text: item.text)
            }
            .sheet(isPresented: $showAddClient) {
                if let inbound = inbound {
                    AddClientSheet(session: session, inbound: inbound, onAdded: { })
                }
            }
            .confirmationDialog("删除这个入站？", isPresented: $confirmInboundDelete, titleVisibility: .visible) {
                Button("删除入站", role: .destructive) {
                    deleteInbound()
                }
                Button("取消", role: .cancel) { }
            } message: {
                if let inbound = inbound {
                    Text("「" + inbound.name + "」和它下面的 " + "\(inbound.clientCount)" + " 个客户端会一起消失。")
                } else {
                    Text("这个操作没法撤销。")
                }
            }
            .confirmationDialog(
                Text("删除客户端「\((pendingClientDelete?.email) ?? "")」？"),
                isPresented: Binding(
                    get: { pendingClientDelete != nil },
                    set: { if !$0 { pendingClientDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingClientDelete
            ) { target in
                Button("删除客户端", role: .destructive) {
                    deleteClient(target)
                    pendingClientDelete = nil
                }
                Button("取消", role: .cancel) {
                    pendingClientDelete = nil
                }
            } message: { _ in
                Text("删掉后这个客户端立刻失效，链接也作废。")
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
        .onAppear {
            guard !didLoad, let inbound = inbound else { return }
            didLoad = true
            remark = inbound.remark
            portText = "\(inbound.port)"
            enabled = inbound.enabled
        }
    }

    // MARK: - 概览

    private func infoCard(_ inbound: InboundSummary) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    InkTag(text: inbound.protocolLabel, tint: Ink.indigo)
                    Text(":" + "\(inbound.port)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Ink.inkSoft)
                    Spacer(minLength: 0)
                    InkTag(
                        text: inbound.enabled ? "已启用" : "已停用",
                        tint: inbound.enabled ? Ink.moss : Ink.inkFaint
                    )
                }

                HStack(spacing: 14) {
                    StatItem(title: "传输", value: inbound.network.uppercased())
                    StatItem(title: "加密", value: inbound.security.uppercased())
                    StatItem(title: "到期", value: PanelFormat.expiry(inbound.expiryTime))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("总流量")
                            .font(.system(size: 10.5))
                            .foregroundColor(Ink.inkFaint)
                        Spacer(minLength: 4)
                        Text(PanelFormat.bytes(inbound.traffic) + " / " + (inbound.total > 0 ? PanelFormat.bytes(inbound.total) : "不限"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Ink.inkSoft)
                    }
                    InkBar(value: inbound.trafficPercent, tint: Ink.indigo)
                }

                if let sni = inbound.tlsServerName {
                    KeyValueRow(title: "SNI", value: sni)
                }
            }
        }
    }

    // MARK: - 编辑

    private func editCard(_ inbound: InboundSummary) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "基本信息", trailing: "改完点保存")

                VStack(alignment: .leading, spacing: 5) {
                    Text("备注")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                    TextField("备注", text: $remark)
                        .font(.system(size: 13))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.75))
                        )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("端口")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                    TextField("端口", text: $portText)
                        .font(.system(size: 13, design: .monospaced))
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.75))
                        )
                }

                Toggle(isOn: $enabled) {
                    Text("启用这个入站")
                        .font(.system(size: 12.5))
                        .foregroundColor(Ink.inkSoft)
                }
                .toggleStyle(SwitchToggleStyle(tint: Ink.moss))

                HStack(spacing: 10) {
                    QuickActionButton(
                        title: session.isWorking ? "保存中" : "保存修改",
                        symbol: "checkmark.circle",
                        tint: Ink.indigo,
                        filled: true,
                        loading: session.isWorking
                    ) {
                        save()
                    }
                    QuickActionButton(title: "重置这个入站的流量", symbol: "arrow.counterclockwise", tint: Ink.cinnabar) {
                        session.resetInboundTraffics(inbound)
                    }
                }
            }
        }
    }

    // MARK: - 客户端

    private func clientsSection(_ inbound: InboundSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionHeader(title: "客户端", count: inbound.clients.count)
                Spacer(minLength: 0)
            }

            Button {
                showAddClient = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("添加客户端")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Ink.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Ink.indigo.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(PlainButtonStyle())

            if inbound.clients.isEmpty {
                PanelHint(text: "这个入站下没有可单独管理的客户端（WireGuard / Dokodemo 这类入站本来就只有一个整体配置）。")
            }

            ForEach(inbound.clients) { client in
                clientCard(inbound: inbound, client: client)
            }
        }
    }

    private func clientCard(inbound: InboundSummary, client: ClientSummary) -> some View {
        let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: session.linkHost)
        let subscription = ShareLinkBuilder.subscriptionURL(
            subId: client.subId,
            settings: session.panelSettings,
            panelURL: session.profile.url
        )
        let copied = copiedId == client.id

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(client.email.isEmpty ? "未命名客户端" : client.email)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(client.enabled ? Ink.ink : Ink.inkFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { client.enabled },
                    set: { value in session.setClientEnabled(inbound: inbound, client: client, enabled: value) }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Ink.moss))
                .disabled(session.isWorking)
            }

            HStack(spacing: 8) {
                Text("↑ " + PanelFormat.bytes(client.up) + "  ↓ " + PanelFormat.bytes(client.down))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                    .lineLimit(1)
                if client.total > 0 {
                    Text("/ " + PanelFormat.bytes(client.total))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer(minLength: 0)
                Text(PanelFormat.expiry(client.expiryTime))
                    .font(.system(size: 10))
                    .foregroundColor(Ink.inkFaint)
            }

            if client.total > 0 {
                InkBar(value: client.trafficPercent, tint: Ink.moss, height: 3.5)
            }

            HStack(spacing: 8) {
                if let link = link {
                    ChipButton(title: copied ? "已复制" : "复制链接", symbol: "link", active: copied) {
                        UIHelpers.copyToPasteboard(link)
                        copiedId = client.id
                        session.showToast("链接已复制")
                    }
                    ChipButton(title: "二维码", symbol: "qrcode") {
                        preview = QRItem(text: link)
                    }
                } else {
                    Text("此协议请到网页里复制链接")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if let subscription = subscription {
                    ChipButton(title: "订阅", symbol: "dot.radiowaves.left.and.right") {
                        preview = QRItem(text: subscription)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    session.resetClientTraffic(inbound: inbound, client: client)
                } label: {
                    Text("清零用量")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Ink.indigo)
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(session.isWorking)

                Button {
                    pendingClientDelete = client
                } label: {
                    Text("删除")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Ink.cinnabar)
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(session.isWorking)

                Spacer(minLength: 0)
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
        .opacity(client.enabled ? 1 : 0.72)
    }

    // MARK: - 危险区

    private func dangerCard(_ inbound: InboundSummary) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "删除", trailing: "不可恢复")
                Text("如果只是临时不想用，先停用；删除会把入站和客户端一起从面板移除。")
                    .font(.system(size: 11))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    confirmInboundDelete = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                        Text("删除这个入站")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Ink.cinnabar)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Ink.cinnabar.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(session.isWorking)
            }
        }
    }

    // MARK: - 动作

    private func save() {
        guard let inbound = inbound else { return }
        let text = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(text), port > 0, port < 65536 else {
            session.showToast("端口要填 1–65535 之间的数字")
            return
        }
        let name = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        session.updateInbound(id: inbound.id, remark: name, port: port, enabled: enabled) { _ in }
    }

    private func deleteInbound() {
        guard let inbound = inbound else { return }
        session.deleteInbound(inbound) { ok in
            if ok {
                dismiss()
            }
        }
    }

    private func deleteClient(_ target: ClientSummary) {
        guard let inbound = inbound else { return }
        session.deleteClient(inbound: inbound, client: target) { _ in }
    }

    /// 详情本身是 sheet，先收起再交给上层打开网页，避免两层模态互相抢。
    private func openWebPanel() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onWeb()
        }
    }

    private func copyAllLinks() {
        guard let inbound = inbound else { return }
        var links: [String] = []
        for client in inbound.clients {
            if let link = ShareLinkBuilder.link(for: inbound, client: client, fallbackHost: session.linkHost) {
                links.append(link)
            }
        }
        guard !links.isEmpty else {
            session.showToast("这个入站没有可复制的链接")
            return
        }
        UIHelpers.copyToPasteboard(links.joined(separator: "\n"))
        session.showToast("已复制 \(links.count) 条链接")
    }
}
