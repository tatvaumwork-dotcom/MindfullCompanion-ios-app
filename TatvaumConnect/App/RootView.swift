import SwiftUI

/// Animated launch screen → onboarding → four tabs (Chat, Planets, 3rd Eye, Profile). Settings opens from the gear.
struct RootView: View {
    let c: AppContainer
    @State private var splashDone = false

    var body: some View {
        ZStack {
            CosmicBackground {
                if !c.profileStore.profile.isOnboarded {
                    let adding = c.profiles.isAddingActive
                    OnboardingView(profileStore: c.profileStore, pincodes: c.pincodes, cities: c.cities,
                                   onCancel: adding ? { c.profiles.cancelAdding() } : nil,
                                   onDone: {
                                       c.profiles.finishAdding()
                                       AppRouter.shared.requestedTab = AppRouter.profileTab
                                   })
                        .frame(maxWidth: 640)  // readable width on iPad
                        .id(c.profiles.active.id)
                } else {
                    MainTabs(c: c)
                }
            }
            if !splashDone {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { splashDone = true } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { KeyboardDismisser.shared.install() }
        // Opened from the Third Eye widget.
        .onOpenURL { url in
            if url.host() == "third-eye" { AppRouter.shared.requestedTab = AppRouter.thirdEyeTab }
        }
    }
}

private struct MainTabs: View {
    let c: AppContainer
    @State private var tab = 0
    @State private var showSettings = false
    @State private var showSky = false
    @State private var showConversations = false
    @State private var openSession: ConversationSummary?
    @State private var guideTargets = GuideTargets()
    /// First-run tour of the tabs; shown once, replayable from Settings.
    @State private var touring = !GuidePrefs.isDone
    private let router = AppRouter.shared

    var body: some View {
        let id = c.profiles.active.id
        ZStack {
            TabView(selection: $tab) {
                ChatView(chat: c.chat, llm: c.llm, name: c.profileStore.profile.displayName,
                         openSettings: { showSettings = true },
                         openConversations: { withAnimation(.snappy) { showConversations = true } })
                    .id(id).background(TabBarProbe())
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(0)
                PlanetsView(profile: c.profileStore.profile, openSettings: { showSettings = true }, onOpenSky: { showSky = true })
                    .id(id).background(TabBarProbe())
                    .tabItem { Label("Planets", systemImage: "globe") }.tag(1)
                ThirdEyeView(store: c.thirdEye, openSettings: { showSettings = true })
                    .background(TabBarProbe())
                    .tabItem { Label("3rd Eye", systemImage: "eye") }.tag(2)
                ProfileView(profileStore: c.profileStore, historyStore: c.historyStore, openSettings: { showSettings = true })
                    .id(id).background(TabBarProbe())
                    .tabItem { Label("Profile", systemImage: "person") }.tag(3)
            }
            .toolbarBackground(Color(argb: 0xF00A0B1A), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if showConversations {
                ConversationsDrawer(summaries: c.historyStore.summaries,
                                    onClose: { withAnimation(.snappy) { showConversations = false } },
                                    onOpen: { s in
                                        withAnimation(.snappy) { showConversations = false }
                                        openSession = s
                                    })
                    .zIndex(1)
            }
            if touring {
                GuideOverlay(targets: guideTargets, onShowTab: { tab = $0 }, onFinish: endTour).zIndex(2)
            }
        }
        .environment(\.guideTargets, guideTargets)
        .sheet(isPresented: $showSettings) {
            SettingsView(profiles: c.profiles, onBack: { showSettings = false },
                         onAddProfile: { showSettings = false; c.profiles.addProfile() },
                         onReplayGuide: { showSettings = false; tab = 0; touring = true })
        }
        .sheet(item: $openSession) { s in
            NavigationStack {
                SessionDetailView(summary: s)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { openSession = nil } } }
            }
        }
        .fullScreenCover(isPresented: $showSky) { SkyCover(c: c) { showSky = false } }
        // Opened from the weekly notification or widget, or birth details just entered: jump to that tab.
        .onChange(of: router.requestedTab, initial: true) { _, t in
            guard let t else { return }
            tab = t; showSettings = false; showSky = false; showConversations = false
            router.requestedTab = nil
        }
        .onChange(of: id) { showConversations = false; openSession = nil }
    }

    private func endTour() {
        withAnimation { touring = false }
        GuidePrefs.isDone = true
    }
}

/// Reports where the bottom tab bar sits for the tour: everything below the tab's content.
/// The tour clips it to the screen, and skips it where nothing is below (e.g. iPad's top tab bar).
private struct TabBarProbe: View {
    @Environment(\.guideTargets) private var targets
    var body: some View {
        GeometryReader { g in
            Color.clear
                .onChange(of: rect(g), initial: true) { _, r in if let r { targets?.rects[.tabBar] = r } }
                .onDisappear { targets?.rects[.tabBar] = nil }
        }
    }
    private func rect(_ g: GeometryProxy) -> CGRect? {
        let f = g.frame(in: .global)
        return CGRect(x: f.minX + 8, y: f.maxY, width: f.width - 16, height: 200)
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
