import SwiftUI

struct ServerListView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings

    var onOpen: (ServerProfile) -> Void
    var onWeb: (ServerProfile) -> Void
    var onEdit: (ServerProfile) -> Void
    var onAdd: () -> Void
    var onSettings: () -> Void

    @State private var confirmDelete: ServerProfile?

    var body: some View {
        ZStack {
            PaperBackground()

            if store.servers.isEmpty {
                emptyState
            } else {
                List {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))

                    ForEach(store.servers) { profile in
                        row(for: profile)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .contextMenu {
                                Button {
                                    onOpen(profile)
                                } label: {
                                    Label("原生面板", systemImage: "square.grid.2x2")
                                }
                                Button {
                                    onWeb(profile)
                                } label: {
                                    Label("原版网页", systemImage: "safari")
                                }
                                Button {
                                    onEdit(profile)
                                } label: {
                                    Label("编辑", systemImage: "square.and.pencil")
                                }
                                Button {
                                    store.moveToTop(id: profile.id)
                                } label: {
                                    Label("移到最前", systemImage: "arrow.up.to.line")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    confirmDelete = profile
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmDelete = profile
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    onEdit(profile)
                                } label: {
                                    Label("编辑", systemImage: "slider.horizontal.3")
                                }
                                .tint(Ink.indigo)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    onWeb(profile)
                                } label: {
                                    Label("网页", systemImage: "safari")
                                }
                                .tint(Ink.moss)
                            }
                    }
                    .onMove { source, destination in
                        store.move(from: source, to: destination)
                    }
                    .onDelete { offsets in
                        store.delete(at: offsets)
                    }

                    footer
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 20))
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    EditButton()
                        .font(.system(size: 14))
                        .foregroundColor(Ink.inkSoft)
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundColor(Ink.ink)
                    }
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Ink.paper)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Ink.ink))
                    }
                }
            }
        }
        .confirmationDialog(
            Text("删除「\(confirmDelete?.name ?? "")」？"),
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { profile in
            Button("删除服务器", role: .destructive) {
                store.delete(id: profile.id)
                confirmDelete = nil
            }
            Button("取消", role: .cancel) {
                confirmDelete = nil
            }
        } message: { _ in
            Text("只删除这台服务器的地址与保存在钥匙串里的账号密码。")
        }
    }

    // MARK: - 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkHeader(
                title: "3x-ui 面板",
                subtitle: store.servers.isEmpty ? "把 VPS 上的面板装进手机" : "\(store.servers.count) 台服务器",
                seal: "墨"
            )
            Text("点开即进入原生 App 界面：概览、入站、订阅、工具四个页签，右上角可随时切到原版网页。")
                .font(.system(size: 12))
                .foregroundColor(Ink.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                    Text("添加服务器")
                        .font(Ink.serif(15, .medium))
                }
                .foregroundColor(Ink.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Ink.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            Text("长按拖动可调整顺序；左滑打开原版网页；长按可建原生面板。")
                .font(.system(size: 11))
                .foregroundColor(Ink.inkFaint)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            InkEmptyMark()
            VStack(spacing: 8) {
                Text("还没有面板")
                    .font(Ink.serif(22, .semibold))
                    .foregroundColor(Ink.ink)
                Text("把 3x-ui 的地址填进来：\nhttps://1.2.3.4:2053/你的路径")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Ink.inkFaint)
                    .lineSpacing(4)
            }
            Button(action: onAdd) {
                Text("添加第一台服务器")
                    .font(Ink.serif(15, .medium))
                    .foregroundColor(Ink.paper)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Ink.cinnabar))
                    .shadow(color: Ink.cinnabar.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            Spacer()
            Button(action: onSettings) {
                Text("设置")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.inkFaint)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 30)
    }

    // MARK: - 行

    private func row(for profile: ServerProfile) -> some View {
        HStack(spacing: 13) {
            InkSeal(text: profile.sealCharacter, size: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(Ink.serif(16.5, .semibold))
                    .foregroundColor(Ink.ink)
                    .lineLimit(1)
                Text(profile.hostAndPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    InkTag(text: profile.userAgent.shortTitle, tint: Ink.indigo)
                    if profile.trustSelfSigned {
                        InkTag(text: "自签", tint: Ink.moss)
                    }
                    if profile.isUsingHTTP {
                        InkTag(text: "HTTP", tint: Ink.cinnabar)
                    }
                    if store.hasSavedLogin(for: profile.id) {
                        InkTag(text: "已存账号", tint: Ink.gold)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                onWeb(profile)
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Ink.indigo)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Ink.indigo.opacity(0.1)))
            }
            .buttonStyle(BorderlessButtonStyle())

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Ink.ink.opacity(0.25))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Ink.ink.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: Ink.ink.opacity(0.05), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen(profile)
        }
    }
}
