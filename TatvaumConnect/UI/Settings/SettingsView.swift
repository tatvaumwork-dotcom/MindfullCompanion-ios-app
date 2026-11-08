import SwiftUI

struct SettingsView: View {
    let profileStore: ProfileStore
    let onBack: () -> Void
    @State private var confirmReset = false

    init(profileStore: ProfileStore, onBack: @escaping () -> Void) {
        self.profileStore = profileStore; self.onBack = onBack
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    SectionCard(title: "About the AI") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(Cosmic.gold)
                            Text("Replies are written by Google Gemini. To personalise them, your messages and profile details are sent to Google when you chat. Your profile and history are stored only on this phone.")
                                .font(.system(size: 14)).foregroundStyle(Cosmic.starText)
                        }
                    }
                    SectionCard(title: "Birth details") {
                        ActionRow(icon: "calendar.badge.clock", text: "Re-enter birth details") { confirmReset = true }
                    }
                    Text("Place data © GeoNames (geonames.org), CC BY 4.0. Star and constellation data © d3-celestial (Olaf Frohn), BSD-3-Clause.")
                        .font(.caption).foregroundStyle(Cosmic.muted).multilineTextAlignment(.center)
                    Text("Tatvaum \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption).foregroundStyle(Cosmic.muted)
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
            }
            .background(CosmicBackground { EmptyView() })
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: onBack) { Image(systemName: "chevron.left") }.accessibilityLabel("Back") } }
            .alert("Re-enter birth details?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { profileStore.resetOnboarding(); onBack() }
            } message: {
                Text("This clears your birth details and chart. Traits, interests, values and goals are kept.")
            }
        }
    }
}
