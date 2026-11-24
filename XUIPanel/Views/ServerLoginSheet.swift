import SwiftUI

/// 原生面板里直接登录：输入面板账号密码，登录成功后写进钥匙串。
struct ServerLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: PanelSession
    var initialUsername: String = ""

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var twoFactorCode: String = ""
    @State private var didLoad = false
    @State private var localError: String?

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        InkCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    InkSeal(text: session.profile.sealCharacter, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("登录 " + session.profile.name)
                                            .font(Ink.serif(15, .semibold))
                                            .foregroundColor(Ink.ink)
                                            .lineLimit(1)
                                        Text(session.profile.hostAndPath)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(Ink.inkFaint)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }

                                Text("原生界面用的是 3x-ui 的 API 接口，需要面板账号密码。登录一次就会存进钥匙串，之后不用再填。")
                                    .font(.system(size: 11))
                                    .foregroundColor(Ink.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("用户名")
                                        .font(.system(size: 10))
                                        .foregroundColor(Ink.inkFaint)
                                    TextField("admin", text: $username)
                                        .font(.system(size: 13))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(Color.white.opacity(0.75))
                                        )
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("密码")
                                        .font(.system(size: 10))
                                        .foregroundColor(Ink.inkFaint)
                                    SecureField("面板密码", text: $password)
                                        .font(.system(size: 13))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(Color.white.opacity(0.75))
                                        )
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("两步验证码（未开启留空）")
                                        .font(.system(size: 10))
                                        .foregroundColor(Ink.inkFaint)
                                    TextField("面板开了 2FA 就填当前 6 位数字", text: $twoFactorCode)
                                        .font(.system(size: 13, design: .monospaced))
                                        .keyboardType(.numberPad)
                                        .textContentType(.oneTimeCode)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(Color.white.opacity(0.75))
                                        )
                                }

                                if let message = localError ?? session.loginError {
                                    Text(message)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(Ink.cinnabar)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Button {
                                    submit()
                                } label: {
                                    HStack(spacing: 7) {
                                        if session.isWorking {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: Ink.paper))
                                                .scaleEffect(0.75)
                                        } else {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .font(.system(size: 14))
                                        }
                                        Text(session.isWorking ? "正在登录…" : "登录")
                                            .font(Ink.serif(15, .medium))
                                    }
                                    .foregroundColor(Ink.paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Ink.ink)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(session.isWorking)
                            }
                        }

                        Text("3x-ui v3 要求先取 CSRF 令牌再登录，已处理好；老版本 v2 会自动跳过。两步验证码只在登录时用一次，不会存进钥匙串。")
                            .font(.system(size: 10.5))
                            .foregroundColor(Ink.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("登录面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Ink.inkSoft)
                }
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            username = initialUsername
        }
    }

    private func submit() {
        localError = nil
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        guard !name.isEmpty || !secret.isEmpty else {
            localError = "用户名和密码都填一下吧"
            return
        }
        session.login(username: name, password: secret, twoFactorCode: twoFactorCode) { ok in
            if ok {
                dismiss()
            } else {
                localError = session.loginError ?? "登录失败，检查账号密码或面板地址"
            }
        }
    }
}
