import SwiftUI

/// 为某个入站添加客户端：邮箱、流量、到期、同时在线 IP 与 flow。
struct AddClientSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: PanelSession
    var inbound: InboundSummary
    var onAdded: () -> Void

    @State private var draft = ClientDraft()
    @State private var formError: String?

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        infoCard
                        formCard
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
            .navigationTitle("添加客户端")
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
                            Text("添加")
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
    }

    private var infoCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    InkTag(text: inbound.protocolLabel, tint: Ink.indigo)
                    Text(inbound.name)
                        .font(Ink.serif(14, .semibold))
                        .foregroundColor(Ink.ink)
                        .lineLimit(1)
                    Text(":" + "\(inbound.port)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                    Spacer(minLength: 0)
                }
                Text(identifierNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identifierNote: String {
        switch inbound.protocolName {
        case "vless", "vmess":
            return "标识留空会自动生成一个 UUID。"
        case "trojan", "shadowsocks":
            return "标识留空会自动生成一个强密码。"
        default:
            return "标识留空会自动生成。"
        }
    }

    private var formCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                field(title: "邮箱 / 备注名", placeholder: "留空自动生成") {
                    TextField("自动生成", text: $draft.email)
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                HStack(spacing: 10) {
                    field(title: "流量（GB）", placeholder: "不限") {
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

                field(title: "同时在线 IP（0 为不限）", placeholder: "0") {
                    TextField("0", text: $draft.limitIp)
                        .font(.system(size: 13, design: .monospaced))
                        .keyboardType(.numberPad)
                }

                if inbound.protocolName == "vless" {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("flow")
                            .font(.system(size: 10))
                            .foregroundColor(Ink.inkFaint)
                        Picker("flow", selection: $draft.flow) {
                            Text("无").tag("")
                            Text("xtls-rprx-vision").tag("xtls-rprx-vision")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }

                field(title: "标识（UUID / 密码）", placeholder: "留空自动生成") {
                    TextField("留空自动生成", text: $draft.identifier)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Toggle(isOn: $draft.enable) {
                    Text("添加后立即启用")
                        .font(.system(size: 12.5))
                        .foregroundColor(Ink.inkSoft)
                }
                .toggleStyle(SwitchToggleStyle(tint: Ink.moss))
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
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14))
                }
                Text(session.isWorking ? "正在添加…" : "添加客户端")
                    .font(Ink.serif(15, .medium))
            }
            .foregroundColor(Ink.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Ink.cinnabar)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(session.isWorking)
    }

    private func create() {
        formError = nil
        session.addClient(to: inbound, draft: draft) { ok in
            if ok {
                onAdded()
                dismiss()
            } else {
                formError = "添加失败，检查一下面板日志或原版网页里的提示。"
            }
        }
    }
}
