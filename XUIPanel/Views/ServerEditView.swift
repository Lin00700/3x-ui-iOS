import SwiftUI

struct ServerEditView: View {
    @EnvironmentObject private var store: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ServerDraft
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var testState: TestState = .idle

    private let isNew: Bool

    private enum TestState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    init(draft: ServerDraft, isNew: Bool) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section(title: "名称") {
                            TextField("例如：香港 · 甲骨文", text: $draft.name)
                                .font(.system(size: 15))
                                .inkField()
                        }

                        section(title: "面板地址", note: "支持 https:// 与 http://，可带自定义路径，例如 https://1.2.3.4:2053/mypanel") {
                            TextField("https://1.2.3.4:2053/路径", text: $draft.urlString)
                                .font(.system(size: 14, design: .monospaced))
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .inkField()

                            if !draft.urlString.isEmpty && draft.normalizedURL == nil {
                                Label("地址格式不对，需要 http(s):// 加主机与端口", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 11))
                                    .foregroundColor(Ink.cinnabar)
                            }
                        }

                        section(title: "账号密码", note: "可留空。保存后写入 iOS 钥匙串，不会出现在任何明文配置里。") {
                            TextField("用户名", text: $draft.username)
                                .font(.system(size: 15))
                                .textContentType(.username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .inkField()

                            SecureField("密码", text: $draft.password)
                                .font(.system(size: 15))
                                .textContentType(.password)
                                .inkField()
                        }

                        section(title: "连接偏好") {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle(isOn: $draft.trustSelfSigned) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("信任自签证书")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Ink.ink)
                                        Text("面板用自签 HTTPS 时打开；公网证书无需打开。")
                                            .font(.system(size: 11))
                                            .foregroundColor(Ink.inkFaint)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: Ink.moss))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("默认显示")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Ink.inkSoft)
                                    Picker("默认显示", selection: $draft.userAgent) {
                                        ForEach(UserAgentMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    Text("电脑版把宽表格按 1280 宽渲染，看得全；手机版用 3x-ui 的响应式布局。")
                                        .font(.system(size: 11))
                                        .foregroundColor(Ink.inkFaint)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                        }

                        testSection

                        if !isNew {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("删除这台服务器", systemImage: "trash")
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Ink.cinnabar.opacity(0.4), lineWidth: 1)
                                    )
                                    .foregroundColor(Ink.cinnabar)
                            }
                        }

                        if let errorMessage = errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(Ink.cinnabar)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isNew ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Ink.inkSoft)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Ink.cinnabar)
                }
            }
            .confirmationDialog("删除这台服务器？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.delete(id: draft.id)
                    dismiss()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("地址与钥匙串里的账号密码都会被移除。")
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
    }

    // MARK: - 子视图

    private func section<Content: View>(title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Ink.serif(14, .semibold))
                .foregroundColor(Ink.inkSoft)
            content()
            if let note = note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(Ink.inkFaint)
                    .lineSpacing(2)
            }
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                runTest()
            } label: {
                HStack(spacing: 8) {
                    if testState == .testing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(testState == .testing ? "正在连接…" : "测试连接")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Ink.indigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Ink.indigo.opacity(0.1))
                )
            }
            .disabled(testState == .testing)

            switch testState {
            case .success(let code):
                Label("收到 HTTP \(code)，面板有响应", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.moss)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.cinnabar)
            case .testing, .idle:
                EmptyView()
            }
        }
    }

    // MARK: - 动作

    private func runTest() {
        guard let url = draft.normalizedURL else {
            errorMessage = "先填一个有效的面板地址"
            return
        }
        errorMessage = nil
        testState = .testing
        ConnectionTester.check(url: url, trustSelfSigned: draft.trustSelfSigned) { result in
            switch result {
            case .success(let code):
                testState = .success(code)
            case .failure(let message):
                testState = .failure(message)
            }
        }
    }

    private func save() {
        guard draft.normalizedURL != nil else {
            errorMessage = "面板地址无效，检查协议与端口"
            return
        }
        let name = draft.resolvedName
        if name.isEmpty {
            errorMessage = "给这台服务器起个名字"
            return
        }
        var toSave = draft
        toSave.name = name
        store.save(draft: toSave)
        dismiss()
    }
}
