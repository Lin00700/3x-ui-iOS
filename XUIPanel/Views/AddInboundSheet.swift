import SwiftUI

/// 新建入站：协议、端口、加密方式、传输方式与首个客户端都在这里配好。
struct AddInboundSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: PanelSession

    @State private var draft = InboundDraft()
    @State private var formError: String?
    @State private var didPrefill = false

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        protocolCard
                        basicCard
                        streamCard
                        clientCard
                        if let formError = formError {
                            Text(formError)
                                .font(.system(size: 11.5))
                                .foregroundColor(Ink.cinnabar)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        submitButton
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("新建入站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Ink.inkSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        create()
                    } label: {
                        if session.isWorking {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("创建")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Ink.cinnabar)
                        }
                    }
                    .disabled(session.isWorking)
                }
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            if let settings = session.panelSettings {
                draft.certFile = settings.webCertFile
                draft.keyFile = settings.webKeyFile
            }
        }
    }

    // MARK: - 协议

    private var protocolCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "协议")

                HStack(spacing: 8) {
                    ForEach(InboundProtocol.allCases) { item in
                        Button {
                            select(protocol: item)
                        } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: item == draft.protocolType ? .semibold : .regular))
                                .foregroundColor(item == draft.protocolType ? Ink.paper : Ink.inkSoft)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(item == draft.protocolType ? Ink.ink : Ink.ink.opacity(0.05))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Text(protocolNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var protocolNote: String {
        switch draft.protocolType {
        case .vless:
            return "VLESS 最通用，支持 Reality（不需要证书）。"
        case .vmess:
            return "VMess 兼容老客户端，建议配 WS 传输。"
        case .trojan:
            return "Trojan 需要 TLS 证书，伪装成正常 HTTPS。"
        case .shadowsocks:
            return "Shadowsocks 只有密码，没有 TLS / Reality，兼容性最好。"
        }
    }

    private func select(protocol item: InboundProtocol) {
        draft.protocolType = item
        if !item.supportsTLS {
            draft.security = .none
        } else if draft.security == .none {
            draft.security = .reality
        }
    }

    // MARK: - 基本信息

    private var basicCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "基本信息")

                field(title: "备注", placeholder: "比如 东京 1 号") {
                    TextField("东京 1 号", text: $draft.remark)
                        .font(.system(size: 13))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("端口")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                    HStack(spacing: 8) {
                        TextField("留空则随机", text: $draft.port)
                            .font(.system(size: 13, design: .monospaced))
                            .keyboardType(.numberPad)
                        Button {
                            draft.port = "\(PanelRandom.port())"
                        } label: {
                            Text("随机")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Ink.indigo)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Ink.indigo.opacity(0.1)))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                    )
                }

                field(title: "监听地址", placeholder: "留空即全部网卡") {
                    TextField("0.0.0.0", text: $draft.listen)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
            }
        }
    }

    private func field<Content: View>(title: String, placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Ink.inkFaint)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 传输与加密

    private var streamCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "传输与加密")

                if draft.protocolType.supportsTLS {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("加密")
                            .font(.system(size: 10))
                            .foregroundColor(Ink.inkFaint)
                        Picker("加密", selection: $draft.security) {
                            ForEach(InboundSecurity.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("传输")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                    Picker("传输", selection: $draft.network) {
                        ForEach(InboundNetwork.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                if draft.security == .reality && draft.protocolType.supportsTLS {
                    field(title: "Reality 伪装目标", placeholder: "www.microsoft.com:443") {
                        TextField("www.microsoft.com:443", text: $draft.realityDest)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    field(title: "SNI（serverName）", placeholder: "留空则用伪装目标的域名") {
                        TextField("www.microsoft.com", text: $draft.serverName)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    Text("Reality 密钥对由 App 现生成，建好后在客户端链接里就能直接连。")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if draft.security == .tls && draft.protocolType.supportsTLS {
                    field(title: "证书 fullchain 路径", placeholder: "/root/cert/fullchain.pem") {
                        TextField("/root/cert/fullchain.pem", text: $draft.certFile)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    field(title: "私钥路径", placeholder: "/root/cert/privkey.pem") {
                        TextField("/root/cert/privkey.pem", text: $draft.keyFile)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    field(title: "SNI（serverName）", placeholder: "证书对应的域名") {
                        TextField("example.com", text: $draft.serverName)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    Text("证书路径要填服务器上的绝对路径；不知道的话先用 Reality，不需要证书。")
                        .font(.system(size: 10))
                        .foregroundColor(Ink.inkFaint)
                }

                if draft.network == .ws {
                    field(title: "WS 路径", placeholder: "/ws") {
                        TextField("/ws", text: $draft.wsPath)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    field(title: "Host 头", placeholder: "留空则不设置") {
                        TextField("example.com", text: $draft.wsHost)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }

                if draft.network == .grpc {
                    field(title: "gRPC serviceName", placeholder: "grpc") {
                        TextField("grpc", text: $draft.grpcService)
                            .font(.system(size: 12, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }
            }
        }
    }

    // MARK: - 首个客户端

    private var clientCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "第一个客户端", trailing: "留空自动生成")

                field(title: "邮箱 / 备注名", placeholder: "自动生成") {
                    TextField("自动生成", text: $draft.email)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                HStack(spacing: 10) {
                    field(title: "流量配额（GB）", placeholder: "不限") {
                        TextField("不限", text: $draft.totalGB)
                            .font(.system(size: 13, design: .monospaced))
                            .keyboardType(.decimalPad)
                    }
                    field(title: "到期（天）", placeholder: "永久") {
                        TextField("永久", text: $draft.expiryDays)
                            .font(.system(size: 13, design: .monospaced))
                            .keyboardType(.numberPad)
                    }
                }

                Toggle(isOn: $draft.enable) {
                    Text("创建后立即启用")
                        .font(.system(size: 12.5))
                        .foregroundColor(Ink.inkSoft)
                }
                .toggleStyle(SwitchToggleStyle(tint: Ink.moss))
            }
        }
    }

    private var submitButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 7) {
                if session.isWorking {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Ink.paper))
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                }
                Text(session.isWorking ? "正在创建…" : "创建入站")
                    .font(Ink.serif(15, .medium))
            }
            .foregroundColor(Ink.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Ink.cinnabar)
            )
            .shadow(color: Ink.cinnabar.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(session.isWorking)
    }

    private func create() {
        formError = nil
        session.addInbound(draft: draft) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                formError = error.localizedDescription
            }
        }
    }
}
