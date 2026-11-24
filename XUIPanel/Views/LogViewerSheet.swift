import SwiftUI

/// 等宽日志查看器：面板日志 / Xray 日志，可换行数、复制、分享。
struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: PanelSession
    var xray: Bool

    @State private var count = 200

    private var text: String {
        if session.logs.isEmpty { return "" }
        return session.logs.joined(separator: "\n")
    }

    var body: some View {
        NavigationView {
            ZStack {
                PaperBackground()

                VStack(spacing: 0) {
                    controls
                    logArea
                }
            }
            .navigationTitle(xray ? "Xray 日志" : "面板日志")
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
                            session.loadLogs(xray: xray, count: count)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Button {
                            if !text.isEmpty {
                                UIHelpers.copyToPasteboard(text)
                                session.showToast("日志已复制")
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Button {
                            if !text.isEmpty {
                                UIHelpers.share(items: [text])
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(Ink.ink)
                }
            }
        }
        .navigationViewStyle(.stack)
        .privacyLock()
        .onAppear {
            session.loadLogs(xray: xray, count: count)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("行数", selection: $count) {
                Text("100").tag(100)
                Text("200").tag(200)
                Text("500").tag(500)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: count) { value in
                session.loadLogs(xray: xray, count: value)
            }

            HStack(spacing: 6) {
                if session.isLoadingLogs {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("正在读取…")
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.inkFaint)
                } else if let error = session.logError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.cinnabar)
                        .lineLimit(2)
                } else {
                    Text("共 \(session.logs.count) 行")
                        .font(.system(size: 10.5))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var logArea: some View {
        if session.logs.isEmpty && session.isLoadingLogs {
            Spacer()
            ProgressView()
            Spacer()
        } else if session.logs.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "text.alignleft")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(Ink.ink.opacity(0.3))
                Text("没有读到日志")
                    .font(Ink.serif(14, .medium))
                    .foregroundColor(Ink.ink)
                Text("有些版本把日志只放在网页里，可以用「原版网页」打开面板查看。")
                    .font(.system(size: 11))
                    .foregroundColor(Ink.inkFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
            }
        } else {
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Ink.inkSoft)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }
}
