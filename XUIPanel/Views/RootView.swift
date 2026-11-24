import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings

    @State private var route: Route?
    @State private var editingDraft: ServerDraft?
    @State private var showSettings = false

    private enum Route: Identifiable {
        case panel(ServerProfile)
        case quick(ServerProfile)

        var id: String {
            switch self {
            case .panel(let profile): return "panel-\(profile.id.uuidString)"
            case .quick(let profile): return "quick-\(profile.id.uuidString)"
            }
        }
    }

    var body: some View {
        NavigationView {
            ServerListView(
                onOpen: { profile in route = .panel(profile) },
                onQuick: { profile in route = .quick(profile) },
                onEdit: { profile in openEditor(for: profile) },
                onAdd: { addServer() },
                onSettings: { showSettings = true }
            )
            .navigationBarTitle("", displayMode: .inline)
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(item: $route) { route in
            switch route {
            case .panel(let profile):
                PanelScreen(
                    profile: profile,
                    username: store.credentials(for: profile.id).username,
                    password: store.password(for: profile.id)
                )
            case .quick(let profile):
                QuickPanelView(
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
