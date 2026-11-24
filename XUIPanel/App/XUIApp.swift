import SwiftUI
import UIKit

@main
struct XUIApp: App {
    @StateObject private var store = ServerStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = LockManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // List 在 iOS 15 需要手动清掉系统底色，宣纸底才透得上来。
        UITableView.appearance().backgroundColor = .clear

        let barAppearance = UINavigationBarAppearance()
        barAppearance.configureWithTransparentBackground()
        barAppearance.backgroundColor = .clear
        barAppearance.shadowColor = .clear
        barAppearance.titleTextAttributes = [.foregroundColor: UIColor(Ink.ink)]
        UINavigationBar.appearance().standardAppearance = barAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = barAppearance
        UINavigationBar.appearance().compactAppearance = barAppearance
        UINavigationBar.appearance().tintColor = UIColor(Ink.ink)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(lock)
                .privacyLock()
                .onAppear {
                    if settings.privacyLockEnabled && !lock.isLocked {
                        lock.lock()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background, settings.privacyLockEnabled {
                        lock.lock()
                    }
                }
        }
    }
}
