import SwiftUI

/// Onboarding → four tabs (Chat, Planets, 3rd Eye, Profile). Settings opens from the gear.
struct RootView: View {
    let c: AppContainer
    var body: some View {
        CosmicBackground {
            if c.profileStore.profile.isOnboarded { MainTabs(c: c) }
            else { OnboardingView(profileStore: c.profileStore, pincodes: c.pincodes, cities: c.cities).frame(maxWidth: 640) }  // readable width on iPad
        }
    }
}

private struct MainTabs: View {
    let c: AppContainer
    @State private var tab = 0
    @State private var showSettings = false
    @State private var sky: (scene: SkyScene, a: Int, b: String)?
    @State private var showSky = false
    private let router = ThirdEyeRouter.shared

    var body: some View {
        TabView(selection: $tab) {
            ChatView(chat: c.chat, llm: c.llm, name: c.profileStore.profile.displayName, openSettings: { showSettings = true })
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            PlanetsView(profile: c.profileStore.profile, openSettings: { showSettings = true }, onOpenSky: { showSky = true })
                .tabItem { Label("Planets", systemImage: "globe") }.tag(1)
            ThirdEyeView(store: c.thirdEye, openSettings: { showSettings = true })
                .tabItem { Label("3rd Eye", systemImage: "eye") }.tag(2)
            ProfileView(profileStore: c.profileStore, historyStore: c.historyStore, openSettings: { showSettings = true })
                .tabItem { Label("Profile", systemImage: "person") }.tag(3)
        }
        .toolbarBackground(Color(argb: 0xF00A0B1A), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showSettings) {
            SettingsView(profileStore: c.profileStore, onBack: { showSettings = false })
        }
        .fullScreenCover(isPresented: $showSky, onDismiss: { sky = nil }) { SkyCover(c: c) { showSky = false } }
        // Opened from the weekly notification: jump straight to the 3rd Eye tab.
        .onChange(of: router.requestedTab) { _, t in
            guard let t else { return }
            tab = t; showSettings = false; showSky = false
            router.requestedTab = nil
        }
    }
}

/// ~5,000 stars and 89 constellations are positioned once, in the background.
private struct SkyCover: View {
    let c: AppContainer
    let close: () -> Void
    @State private var sky: (SkyScene, Int, String)?

    var body: some View {
        ZStack {
            Color(argb: 0xFF03040B).ignoresSafeArea()
            if let sky { SkyView(scene: sky.0, sky.1, sky.2, onClose: close) }
            else { ProgressView().tint(Cosmic.gold) }
        }
        .task {
            let profile = c.profileStore.profile, catalog = c.skyCatalog
            let result = await Task.detached(priority: .userInitiated) { fullSkyFor(profile, catalog) }.value
            if let result { sky = result } else { close() }
        }
    }
}
