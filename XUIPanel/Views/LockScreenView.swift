import SwiftUI

/// 隐私锁画面：整块宣纸盖住底下的地址与账号。
struct LockScreenView: View {
    @EnvironmentObject private var lock: LockManager

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 24) {
                Spacer()

                InkSeal(text: "锁", size: 66)

                VStack(spacing: 8) {
                    Text("面板已上锁")
                        .font(Ink.serif(24, .semibold))
                        .foregroundColor(Ink.ink)
                    Text("已保存的服务器地址与账号都被挡住")
                        .font(.system(size: 12.5))
                        .foregroundColor(Ink.inkFaint)
                }

                Button {
                    lock.authenticate()
                } label: {
                    HStack(spacing: 8) {
                        if lock.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Ink.paper))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text(lock.isAuthenticating ? "验证中…" : "用\(lock.biometryName)解锁")
                            .font(Ink.serif(15, .medium))
                    }
                    .foregroundColor(Ink.paper)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Ink.ink))
                }
                .disabled(lock.isAuthenticating)

                if let message = lock.message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundColor(Ink.cinnabar)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Text("设置里可以关掉隐私锁")
                    .font(.system(size: 11))
                    .foregroundColor(Ink.inkFaint)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
        .onAppear {
            lock.unlockIfNeeded()
        }
    }
}

/// 套在任何一个页面外面的隐私锁遮罩。
struct PrivacyLockModifier: ViewModifier {
    @EnvironmentObject private var lock: LockManager
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        ZStack {
            content

            if settings.privacyLockEnabled && lock.isLocked {
                LockScreenView()
                    .environmentObject(lock)
                    .environmentObject(settings)
                    .zIndex(99)
            }
        }
    }
}

extension View {
    func privacyLock() -> some View {
        modifier(PrivacyLockModifier())
    }
}
