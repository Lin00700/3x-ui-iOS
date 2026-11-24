import SwiftUI
import UIKit

/// 面板页面里抓出来的订阅链接与二维码，统一复制 / 分享。
struct SubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let links: [String]
    let codes: [QRCodeItem]

    @State private var preview: QRPreview?
    @State private var copiedText: String?

    private struct QRPreview: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !codes.isEmpty {
                            sectionTitle("页面里的二维码", note: "长按图片或点分享，直接存进相册 / 发给别人。")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(codes) { code in
                                        codeCard(code)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        if !links.isEmpty {
                            sectionTitle("订阅与分享链接", note: "点一下复制；右侧可生成二维码。")
                            VStack(spacing: 8) {
                                ForEach(Array(links.indices), id: \.self) { index in
                                    linkRow(links[index])
                                }
                            }
                        }

                        if links.isEmpty && codes.isEmpty {
                            Text("这个页面上没有找到订阅链接或二维码。可以打开某个入站客户端详情再试一次。")
                                .font(.system(size: 12.5))
                                .foregroundColor(Ink.inkFaint)
                                .padding(.top, 20)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("订阅 / 二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Ink.inkSoft)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $preview) { item in
            QRPreviewSheet(text: item.text)
        }
        .privacyLock()
    }

    // MARK: - 组件

    private func sectionTitle(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Ink.serif(15, .semibold))
                .foregroundColor(Ink.ink)
            Text(note)
                .font(.system(size: 11))
                .foregroundColor(Ink.inkFaint)
        }
    }

    private func codeCard(_ code: QRCodeItem) -> some View {
        VStack(spacing: 8) {
            if let image = UIHelpers.loadImageSync(from: code.source) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .background(Color.white)
                    .onTapGesture {
                        UIHelpers.share(items: [image])
                    }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Ink.ink.opacity(0.05))
                    .frame(width: 130, height: 130)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 30))
                            .foregroundColor(Ink.inkFaint)
                    )
            }

            Button {
                UIHelpers.loadImage(from: code.source) { image in
                    guard let image = image else { return }
                    UIHelpers.share(items: [image])
                }
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Ink.indigo)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Ink.ink.opacity(0.07), lineWidth: 1)
        )
    }

    private func linkRow(_ link: String) -> some View {
        HStack(spacing: 10) {
            Button {
                UIHelpers.copyToPasteboard(link)
                copiedText = link
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(link)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(copiedText == link ? "已复制" : "点一下复制")
                        .font(.system(size: 10))
                        .foregroundColor(copiedText == link ? Ink.moss : Ink.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                preview = QRPreview(text: link)
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 14))
                    .foregroundColor(Ink.indigo)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Ink.indigo.opacity(0.1)))
            }
            .buttonStyle(BorderlessButtonStyle())

            Button {
                UIHelpers.share(items: [link])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(Ink.inkSoft)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Ink.ink.opacity(0.06), lineWidth: 1)
        )
    }
}

/// 单独一张放大二维码。
struct QRPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                VStack(spacing: 18) {
                    if let image = QRCodeGenerator.image(for: text, scale: 14) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: Ink.ink.opacity(0.12), radius: 16, x: 0, y: 8)
                    }

                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Ink.inkFaint)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button {
                            UIHelpers.copyToPasteboard(text)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Ink.indigo)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Ink.indigo.opacity(0.1)))
                        }

                        Button {
                            if let image = QRCodeGenerator.image(for: text, scale: 14) {
                                UIHelpers.share(items: [image])
                            }
                        } label: {
                            Label("分享图片", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Ink.paper)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Ink.ink))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("二维码")
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
}
