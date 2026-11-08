import SwiftUI

private let profileSignGlyphs = ["♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓"]

private enum TraitSheet: Identifiable {
    case add, edit(PersonalityTrait)
    var id: String { switch self { case .add: "add"; case .edit(let t): t.id } }
    var trait: PersonalityTrait? { if case .edit(let t) = self { t } else { nil } }
}

/// Chart-derived data, computed off the main thread once per set of birth details.
private struct Derived {
    var cosmic: CosmicProfile?
    var dasha: [Vimshottari.Period]?

    static func compute(_ p: UserProfile) async -> Derived {
        guard let dob = p.dateOfBirth, let tob = p.timeOfBirth,
              let ms = ProfileStore.birthMillis(dob, tob, p.birthTimezone) else { return Derived() }
        let lat = p.birthPlaceLatitude, lon = p.birthPlaceLongitude
        return await Task.detached {
            let planets = PlanetPositionCalculator.calculatePlanetPositions(epochMillis: ms)
            let moon = planets.first { $0.planet == .Moon }!
            var d = Derived(dasha: Vimshottari.timeline(birthMillis: ms, moonSiderealLongitude: moon.siderealLongitude))
            if let lat, let lon {
                d.cosmic = CosmicProfile.build(planets: planets, ascendantLongitude: PlanetPositionCalculator.calculateAscendant(epochMillis: ms, latitude: lat, longitude: lon).longitude)
            }
            return d
        }.value
    }
}

struct ProfileView: View {
    let profileStore: ProfileStore
    let historyStore: HistoryStore
    let openSettings: () -> Void

    @State private var derived = Derived()
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var addingTo: ListKind?
    @State private var itemDraft = ""
    @State private var traitSheet: TraitSheet?
    @State private var showChart = false
    @State private var openSessionId: String?

    init(profileStore: ProfileStore, historyStore: HistoryStore, openSettings: @escaping () -> Void) {
        self.profileStore = profileStore; self.historyStore = historyStore; self.openSettings = openSettings
    }

    var body: some View {
        let profile = profileStore.profile
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    header(profile)
                    if let c = derived.cosmic {
                        CosmicProfilePanel(c: c, running: derived.dasha.flatMap { Vimshottari.current(timeline: $0, at: nowMillis()) })
                    }
                    if let t = derived.dasha { DashaPanel(timeline: t) }
                    blueprint(profile)
                    matters(profile)
                    traits(profile)
                    history
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CosmicBackground { EmptyView() })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showChart) { BirthChartView(report: profile.horoscopeReport ?? "") }
            .navigationDestination(item: $openSessionId) { id in
                if let s = historyStore.summaries.first(where: { $0.id == id }) { SessionDetailView(summary: s) }
            }
        }
        .task(id: birthKey(profile)) {
            derived = await Derived.compute(profile)
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty { profileStore.setName(nameDraft) } }
        }
        .alert(addTitle, isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
            TextField("", text: $itemDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let k = addingTo { profileStore.addItem(k, itemDraft) } }
        }
        .sheet(item: $traitSheet) { mode in
            TraitEditorSheet(existing: mode.trait,
                             onSave: { mode.trait == nil ? profileStore.addTrait($0) : profileStore.updateTrait($0) },
                             onDelete: profileStore.deleteTrait)
        }
    }

    private func birthKey(_ p: UserProfile) -> String {
        "\(p.dateOfBirth ?? "")|\(p.timeOfBirth ?? "")|\(p.birthTimezone)|\(p.birthPlaceLatitude ?? 0)|\(p.birthPlaceLongitude ?? 0)"
    }

    private var addTitle: String {
        switch addingTo { case .interests: "Add interest"; case .values: "Add value"; case .goals: "Add goal"; case nil: "" }
    }

    // MARK: Sections

    private func header(_ p: UserProfile) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                CosmicTitle(lead: "Your Cosmic", accent: "Profile")
                Subtitle(p.dateOfBirth.map { "Born \($0) \(p.timeOfBirth ?? "") · \(p.birthTimezone.replacingOccurrences(of: "_", with: " "))" } ?? "A synthesis of your whole chart")
            }
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape.fill").foregroundStyle(Cosmic.muted).frame(width: 44, height: 44) }
                .accessibilityLabel("Settings")
        }
    }

    private func blueprint(_ p: UserProfile) -> some View {
        let insight = p.onboardingInsight ?? ""
        let busy = profileStore.isGeneratingPredictions
        return SectionCard(title: "Cosmic blueprint", trailing: {
            if busy { ProgressView().tint(Cosmic.gold).scaleEffect(0.8) }
            else { Button { profileStore.regeneratePredictions() } label: { Image(systemName: "arrow.clockwise").foregroundStyle(Cosmic.muted) }.accessibilityLabel("Refresh") }
        }) {
            if !insight.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(insight).font(.system(size: 13.5)).lineSpacing(5).foregroundStyle(Color(argb: 0xFFD0D3EE))
            }
            if !p.predictedPersonality.trimmingCharacters(in: .whitespaces).isEmpty {
                if !insight.isEmpty { Divider().overlay(Cosmic.panelBorder) }
                Text("✦ \(p.predictedPersonality)").font(.system(size: 13.5)).lineSpacing(5).foregroundStyle(Color(argb: 0xFFE1E3FA))
            }
            if insight.trimmingCharacters(in: .whitespaces).isEmpty && p.predictedPersonality.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(busy ? "Reading the stars…" : "Tap ↻ to have your companion read your chart.").font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            }
            if p.horoscopeReport != nil {
                Divider().overlay(Cosmic.panelBorder)
                Button { showChart = true } label: {
                    HStack {
                        Text(glyph("☉")).font(.system(size: 18)).foregroundStyle(Cosmic.gold).frame(width: 28, alignment: .leading)
                        Text("Full birth chart").font(.system(size: 15, weight: .semibold)).foregroundStyle(Cosmic.starText)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Cosmic.muted)
                    }.padding(.vertical, 4).contentShape(Rectangle())
                }
            }
        }
    }

    private func matters(_ p: UserProfile) -> some View {
        SectionCard(title: "What matters to you") {
            Button { nameDraft = p.name; editingName = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        FieldLabel("NAME")
                        Text(p.name.isEmpty ? "Tap to set" : p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Cosmic.starText)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Cosmic.muted)
                }.contentShape(Rectangle())
            }
            Divider().overlay(Cosmic.panelBorder)
            EditableList(label: "Interests", items: p.interests, onAdd: { itemDraft = ""; addingTo = .interests }) { profileStore.removeItem(.interests, $0) }
            EditableList(label: "Values", items: p.values, onAdd: { itemDraft = ""; addingTo = .values }) { profileStore.removeItem(.values, $0) }
            EditableList(label: "Goals", items: p.goals, onAdd: { itemDraft = ""; addingTo = .goals }) { profileStore.removeItem(.goals, $0) }
            Divider().overlay(Cosmic.panelBorder)
            FieldLabel("How should I talk with you?")
            TextField("e.g. prefers concise answers", text: Binding(get: { p.communicationNotes }, set: profileStore.setCommunicationNotes), axis: .vertical)
                .lineLimit(2...4).padding(12).foregroundStyle(Cosmic.starText)
                .background(Color(argb: 0x0AFFFFFF), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
        }
    }

    private func traits(_ p: UserProfile) -> some View {
        SectionCard(title: "Traits from your chats", trailing: {
            Button { traitSheet = .add } label: { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Cosmic.gold) }
                .accessibilityLabel("Add trait")
        }) {
            if p.traits.isEmpty {
                Text("Traits appear here as your companion gets to know you.").font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            } else {
                let sorted = p.traits.sorted { TraitCategory.allCases.firstIndex(of: $0.category)! < TraitCategory.allCases.firstIndex(of: $1.category)! }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Divider().overlay(Cosmic.panelBorder) }
                    TraitRow(trait: t) { traitSheet = .edit(t) }
                }
            }
        }
    }

    private var history: some View {
        SectionCard(title: "Past conversations") {
            if historyStore.summaries.isEmpty {
                Text("When you end a chat session, its summary appears here.").font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            } else {
                ForEach(Array(historyStore.summaries.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider().overlay(Cosmic.panelBorder) }
                    SummaryRow(summary: s) { openSessionId = s.id }
                }
            }
        }
    }
}

// MARK: - Cosmic Profile panel

private struct CosmicProfilePanel: View {
    let c: CosmicProfile
    let running: Vimshottari.Current?

    var body: some View {
        GlassPanel {
            SectionTitle("In a nutshell")
            RichText(c.summary)
            SectionTitle("The Big Three")
            HStack(spacing: 8) {
                ForEach([c.sun, c.moon, c.rising], id: \.title) { b in
                    MiniCard(title: b.title, glyph: profileSignGlyphs[b.sign.ordinal], tint: Color(argb: UInt32(CosmicProfile.ELEMENT_COLOR[b.element]!)),
                             name: b.sign.label, sub: b.subtitle)
                }
            }
            if let running {
                SectionTitle("Dasha · Running now")
                HStack(spacing: 8) {
                    ForEach([("Maha · Era", running.maha), ("Antar · Chapter", running.antar), ("Pratyantar · Scene", running.pratyantar)], id: \.0) { t, p in
                        MiniCard(title: t, glyph: p.lord.symbol, tint: p.lord.tint, name: p.lord.label, sub: "until \(monthLabel(p.endMillis))")
                    }
                }
            }
            SectionTitle("Elemental balance"); Bars(bars: c.elements)
            SectionTitle("Modality"); Bars(bars: c.modalities)
            SectionTitle("Life motivation · Pada purusharthas"); Bars(bars: c.purusharthas)
            RichText("Driven most by **\(c.dominantPurushartha)**: \(c.purusharthaText).", color: Color(argb: 0xFFD0D3EE), size: 13)
            SectionTitle("Natural strengths")
            VStack(spacing: 0) { ForEach(Array(c.strengths.enumerated()), id: \.offset) { GlyphItem(glyph: "✦", text: $0.element) } }
            SectionTitle("Growth edges")
            VStack(spacing: 0) { ForEach(Array(c.growthEdges.enumerated()), id: \.offset) { GlyphItem(glyph: "◇", text: $0.element, glyphColor: Color(argb: 0xFFC9CDF0)) } }
            SectionTitle("Soul path · Nodal axis")
            GlyphItem(glyph: glyph("☊"), text: c.northNode, glyphColor: Color(argb: 0xFFC58CFF))
            GlyphItem(glyph: glyph("☋"), text: c.southNode, glyphColor: Color(argb: 0xFF8C6BD6))
            SectionTitle("Your keywords")
            FlowLayout { ForEach(c.keywords, id: \.word) { Pill(text: $0.word, accent: true, emphasised: $0.emphasised) } }
            Note("This profile is generated from traditional meanings of signs, nakshatras, padas, dignities and aspects, weighted by each planet's importance. It is a reflective guide, not a definitive reading.")
                .padding(.top, 6)
        }
    }
}

private struct Bars: View {
    let bars: [CosmicProfile.Bar]
    var body: some View {
        VStack(spacing: 7) { ForEach(bars, id: \.label) { PercentBar(label: $0.label, percent: $0.percent, color: Color(argb: UInt32($0.color)), top: $0.top) } }
    }
}

private struct MiniCard: View {
    let title: String, glyph: String
    let tint: Color
    let name: String, sub: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10.5)).tracking(1).foregroundStyle(Cosmic.muted).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text(glyph).font(.system(size: 26)).foregroundStyle(tint)
            Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Cosmic.starText)
            Text(sub).font(.system(size: 12)).foregroundStyle(Cosmic.muted).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 10).frame(maxWidth: .infinity).frame(height: 132)
        .background(Color(argb: 0x0AFFFFFF), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
    }
}

private struct EditableList: View {
    let label: String, items: [String]
    let onAdd: () -> Void
    let onRemove: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FieldLabel(label.uppercased())
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Cosmic.gold)
                }
            }
            if items.isEmpty { Text("Nothing yet").font(.system(size: 12.5)).foregroundStyle(Cosmic.muted) }
            else { ChipFlow(items: items, accent: true, onRemove: onRemove) }
        }
    }
}

private struct SummaryRow: View {
    let summary: ConversationSummary
    let onView: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Date(timeIntervalSince1970: Double(summary.date) / 1000).formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Cosmic.starText)
                Text("  ·  \(summary.messageCount) messages").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Cosmic.muted)
            }
            Text(summary.summary.isEmpty ? "No summary available." : summary.summary)
                .font(.system(size: 13.5)).lineSpacing(4).foregroundStyle(Color(argb: 0xFFD0D3EE)).lineLimit(expanded ? nil : 2)
            if expanded {
                if !summary.newTraitsExtracted.isEmpty {
                    FieldLabel("TRAITS OBSERVED")
                    ChipFlow(items: summary.newTraitsExtracted, accent: true)
                }
                if !summary.messages.isEmpty {
                    Button(action: onView) {
                        HStack(spacing: 4) { Text("View conversation"); Image(systemName: "chevron.right") }
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Cosmic.gold)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }
}
