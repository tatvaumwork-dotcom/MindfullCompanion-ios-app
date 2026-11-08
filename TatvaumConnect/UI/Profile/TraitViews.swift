import SwiftUI

extension TraitCategory {
    var icon: String {
        switch self {
        case .Personality: "person.fill"
        case .Communication: "bubble.left.fill"
        case .Emotional: "heart.fill"
        case .Intellectual: "brain.head.profile"
        case .Lifestyle: "figure.walk"
        }
    }
}

struct TraitRow: View {
    let trait: PersonalityTrait
    let onTap: () -> Void
    var body: some View {
        let observed = trait.source == .Observed
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: trait.category.icon).foregroundStyle(Cosmic.muted).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trait.text).font(.system(size: 16)).foregroundStyle(Cosmic.starText).multilineTextAlignment(.leading)
                    HStack(spacing: 0) {
                        Text(trait.source.rawValue).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(observed ? Cosmic.goldSoft : Cosmic.muted)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(observed ? Color(argb: 0x2EF5C66B) : Color(argb: 0x0FFFFFFF), in: Capsule())
                        if trait.observedCount > 1 {
                            Text("  ×\(trait.observedCount)").font(.system(size: 11)).foregroundStyle(Cosmic.muted)
                        }
                    }
                }
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Sheet for adding or editing a trait. Edit mode also offers Delete.
struct TraitEditorSheet: View {
    let existing: PersonalityTrait?
    let onSave: (PersonalityTrait) -> Void
    let onDelete: (String) -> Void
    @State private var text: String
    @State private var category: TraitCategory
    @Environment(\.dismiss) private var dismiss

    init(existing: PersonalityTrait?, onSave: @escaping (PersonalityTrait) -> Void, onDelete: @escaping (String) -> Void) {
        self.existing = existing; self.onSave = onSave; self.onDelete = onDelete
        _text = State(initialValue: existing?.text ?? "")
        _category = State(initialValue: existing?.category ?? .Personality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New trait" : "Edit trait").font(.title2.bold()).foregroundStyle(Cosmic.starText)
            TextField("e.g. prefers direct communication", text: $text, axis: .vertical)
                .lineLimit(2...4).padding(12).foregroundStyle(Cosmic.starText)
                .background(Color(argb: 0x0AFFFFFF), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
            FieldLabel("Category")
            FlowLayout(spacing: 8) {
                ForEach(TraitCategory.allCases, id: \.self) { c in
                    Button { category = c } label: {
                        Label(c.label, systemImage: c.icon).font(.system(size: 13))
                            .foregroundStyle(category == c ? Cosmic.onGold : Cosmic.body)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(category == c ? AnyShapeStyle(Cosmic.gold) : AnyShapeStyle(Color(argb: 0x12FFFFFF)), in: Capsule())
                    }
                }
            }
            PrimaryButton(text: "Save", enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if var e = existing { e.text = t; e.category = category; onSave(e) }
                else { onSave(PersonalityTrait(category: category, text: t, source: .Manual)) }
                dismiss()
            }
            if let existing {
                Button(role: .destructive) { onDelete(existing.id); dismiss() } label: {
                    Text("Delete trait").frame(maxWidth: .infinity).frame(height: 44)
                }.foregroundStyle(Cosmic.error)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Cosmic.panelSolid.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
