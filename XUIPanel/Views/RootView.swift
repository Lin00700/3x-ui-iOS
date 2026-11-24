import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings

    @State private var route: Route?
    @State private var editingDraft: ServerDraft?
    @State private var showSettings = false

    private enum Route: Identifiable {
        case native(ServerProfile)
        case web(ServerProfile)

        var id: String {
            switch self {
            case .native(let profile): return "native-\(profile.id.uuidString)"
            case .web(let profile): return "web-\(profile.id.uuidString)"
            }
        }
    }

    var body: some View {
        NavigationView {
            ServerListView(
                onOpen: { profile in route = .native(profile) },
                onWeb: { profile in route = .web(profile) },
                onEdit: { profile in openEditor(for: profile) },
                onAdd: { addServer() },
                onSettings: { showSettings = true }
            )
            .navigationBarTitle("", displayMode: .inline)
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(item: $route) { route in
            switch route {
            case .native(let profile):
                NativePanelShellView(
                    profile: profile,
                    username: store.credentials(for: profile.id).username,
                    password: store.password(for: profile.id)
                )
            case .web(let profile):
                PanelScreen(
                    profile: profile,
                    username: store.credentials(for: profile.id).username,
                    password: store.password(for: profile.id)
                )
            }
        }
        .sheet(item: $editingDraft) { draft in
            ServerEditView(draft: draft, isNew: !store.servers.contains(where: { $0.id == draft.id }))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func addServer() {
        editingDraft = ServerDraft(defaultUserAgent: settings.defaultUserAgent)
    }

    private func openEditor(for profile: ServerProfile) {
        editingDraft = ServerDraft(profile: profile, password: store.password(for: profile.id))
    }
}
