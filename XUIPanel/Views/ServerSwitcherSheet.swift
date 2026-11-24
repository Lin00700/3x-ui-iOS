import SwiftUI

/// 一键在多台 VPS 面板之间切换。
struct ServerSwitcherSheet: View {
    @EnvironmentObject private var store: ServerStore
    @Environment(\.dismiss) private var dismiss

    let currentId: UUID
    var onSelect: (ServerProfile) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.servers) { profile in
                            row(for: profile)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("切换服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Ink.inkSoft)
                }
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
    }

    private func row(for profile: ServerProfile) -> some View {
        let isCurrent = profile.id == currentId
        return Button {
            if !isCurrent {
                onSelect(profile)
            }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                InkSeal(text: profile.sealCharacter, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(Ink.serif(15, .semibold))
                        .foregroundColor(Ink.ink)
                        .lineLimit(1)
                    Text(profile.hostAndPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("当前")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Ink.cinnabar)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.92 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isCurrent ? Ink.cinnabar.opacity(0.28) : Ink.ink.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
