import SwiftUI

struct SettingsView: View {
    let profiles: ProfileManager
    let onBack: () -> Void
    let onAddProfile: () -> Void
    let onReplayGuide: () -> Void
    @State private var confirmReset = false

    var body: some View {
        let profileStore = profiles.active.profileStore
        let name = profileStore.profile.displayName.isEmpty ? "this profile" : profileStore.profile.displayName
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ProfilesSection(profiles: profiles, onAdd: onAddProfile)
                    TraitsSection(profileStore: profileStore, isMe: profiles.active.id == profiles.primaryId)
                        .id(profiles.active.id)
                        .transition(.opacity)
                    SectionCard(title: "About the AI") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(Cosmic.gold)
                            Text("Replies are written by Google Gemini. To personalise them, your messages and profile details are sent to Google when you chat. Your profile and history are stored only on this phone.")
                                .font(.system(size: 14)).foregroundStyle(Cosmic.starText)
                        }
                    }
                    SectionCard(title: "Help") {
                        ActionRow(icon: "safari", text: "Replay the app guide", action: onReplayGuide)
                    }
                    SectionCard(title: "Birth details") {
                        ActionRow(icon: "calendar.badge.clock", text: "Re-enter birth details for \(name)") { confirmReset = true }
                    }
                    Text("Place data © GeoNames (geonames.org), CC BY 4.0. Star and constellation data © d3-celestial (Olaf Frohn), BSD-3-Clause.")
                        .font(.caption).foregroundStyle(Cosmic.muted).multilineTextAlignment(.center)
                    Text("Tatvaum \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption).foregroundStyle(Cosmic.muted)
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
            }
            .background(CosmicBackground { EmptyView() })
            .animation(.snappy, value: profiles.active.id)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: onBack) { Image(systemName: "chevron.left") }.accessibilityLabel("Back") } }
            .alert("Re-enter birth details?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { profileStore.resetOnboarding(); onBack() }
            } message: {
                Text("This clears \(name)'s birth details and chart. Traits, interests, values and goals are kept.")
            }
        }
    }
}

/// Settings → Profiles: switch between up to 5 people, add one, or delete one (not "Me").
private struct ProfilesSection: View {
    let profiles: ProfileManager
    let onAdd: () -> Void
    @State private var deleting: ProfileSlot?

    var body: some View {
        let all = profiles.all
        SectionCard(title: "Profiles · \(all.count) of \(ProfileManager.max)") {
            VStack(spacing: 2) {
                ForEach(all) { slot in
                    ProfileRow(slot: slot, isMe: slot.id == profiles.primaryId, selected: slot.id == profiles.active.id,
                               onSelect: { profiles.switchTo(slot.id) },
                               onDelete: slot.id != profiles.primaryId ? { deleting = slot } : nil)
                }
            }
            if profiles.canAdd {
                Divider().overlay(Cosmic.panelBorder)
                Button(action: onAdd) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.badge.plus").foregroundStyle(Cosmic.gold)
                        Text("Add a profile").font(.system(size: 16)).foregroundStyle(Cosmic.starText)
                        Spacer()
                    }.padding(.vertical, 6).contentShape(Rectangle())
                }
            }
        }
        .alert(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let d = deleting { profiles.delete(d.id) }
                deleting = nil
            }
        } message: {
            Text("This removes their birth details, chats, traits and interests from this phone. It can't be undone.")
        }
    }

    private var deleteTitle: String {
        let n = deleting?.profileStore.profile.displayName ?? ""
        return "Delete \(n.isEmpty ? "this profile" : n)?"
    }
}

private struct ProfileRow: View {
    let slot: ProfileSlot
    let isMe: Bool, selected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        let p = slot.profileStore.profile
        let name = p.displayName.isEmpty ? "Unnamed" : p.displayName
        let born = p.dateOfBirth.flatMap { ThirdEye.date(fromKey: $0) }.map { "Born " + $0.formatted(date: .abbreviated, time: .omitted) }
        let details = [born, p.placeOfBirth.isEmpty ? nil : p.placeOfBirth].compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Text(name.prefix(1).uppercased()).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(selected ? Cosmic.onGold : Cosmic.gold)
                        .frame(width: 42, height: 42).background(selected ? Cosmic.gold : Color(argb: 0x33F5C66B), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Cosmic.starText).lineLimit(1)
                            if isMe {
                                Text("Me").font(.system(size: 11, weight: .semibold)).foregroundStyle(Cosmic.gold)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .overlay(Capsule().stroke(Color(argb: 0x73F5C66B)))
                            }
                        }
                        if !details.isEmpty { Text(details).font(.system(size: 12.5)).foregroundStyle(Cosmic.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Cosmic.gold).accessibilityLabel("Selected") }
                }.contentShape(Rectangle())
            }
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(Cosmic.muted).frame(width: 36, height: 36) }
                    .accessibilityLabel("Delete \(name)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(selected ? Color(argb: 0x14F5C66B) : .clear, in: RoundedRectangle(cornerRadius: 14))
        .buttonStyle(.plain)
    }
}

/// The selected person's traits: what their chart suggests, and what their chats have shown.
private struct TraitsSection: View {
    let profileStore: ProfileStore
    let isMe: Bool

    var body: some View {
        let p = profileStore.profile
        let name = p.displayName.isEmpty ? "Their" : "\(p.displayName)’s"
        let fromChart = Array(p.predictedTraits.prefix(8))
        let fromChats = p.traits.sorted { $0.observedCount > $1.observedCount }.map(\.text)
        SectionCard(title: isMe ? "Your traits" : "\(name) traits") {
            if !fromChart.isEmpty {
                FieldLabel("FROM \(isMe ? "YOUR" : "THEIR") CHART")
                ChipFlow(items: fromChart, accent: true)
            }
            if !fromChart.isEmpty && !fromChats.isEmpty { Divider().overlay(Cosmic.panelBorder) }
            if !fromChats.isEmpty {
                FieldLabel("FROM \(isMe ? "YOUR" : "THEIR") CHATS")
                ChipFlow(items: fromChats)
            }
            if fromChart.isEmpty && fromChats.isEmpty {
                Text(profileStore.isGeneratingPredictions ? "Reading the stars…"
                     : "Traits appear here once the chart has been read and as \(isMe ? "you chat" : "they chat").")
                    .font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            }
        }
    }
}
