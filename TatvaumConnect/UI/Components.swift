import SwiftUI

// MARK: Background

private let starField: [SIMD4<Double>] = {
    var g = SeededRNG(seed: 42)
    return (0..<140).map { _ in SIMD4(g.next(), g.next(), g.next(), g.next()) }
}()

/// Deep-space backdrop behind every screen: soft nebulae and gently twinkling stars.
struct CosmicBackground<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Cosmic.spaceBg.ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    func nebula(_ c: UInt32, _ x: Double, _ y: Double, _ r: Double) {
                        let center = CGPoint(x: w * x, y: h * y)
                        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                                 with: .radialGradient(Gradient(colors: [Color(argb: c), .clear]), center: center, startRadius: 0, endRadius: r))
                    }
                    nebula(0x332A1F5C, 0.15, 0.2, w * 0.9)
                    nebula(0x2A5C2A3A, 0.95, 0.75, w * 0.8)
                    nebula(0x1F1F4A6B, 0.5, 1.05, w)
                    let t = tl.date.timeIntervalSinceReferenceDate / 7
                    for s in starField {
                        let a = (0.15 + s.z * 0.55) * (0.7 + 0.3 * sin((t.truncatingRemainder(dividingBy: 1) + s.w) * 2 * .pi))
                        let r = 0.4 + s.z * 1.1
                        ctx.fill(Path(ellipseIn: CGRect(x: s.x * w - r, y: s.y * h - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(a)))
                    }
                }
            }
            .ignoresSafeArea()
            content
        }
    }
}

/// Small deterministic generator so the star field is stable.
struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: Text

/// "✦ Your Cosmic **Profile**" style heading: white text with a gold accent word.
struct CosmicTitle: View {
    let lead: String, accent: String
    var size: CGFloat = 22
    var body: some View {
        (Text("✦ \(lead) ") + Text(accent).foregroundStyle(Cosmic.gold))
            .font(.system(size: size, weight: .bold)).tracking(0.5).foregroundStyle(Cosmic.starText)
    }
}

struct Subtitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(Cosmic.muted).lineSpacing(3) }
}

/// Uppercase, letter-spaced section heading.
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.4).foregroundStyle(Cosmic.muted)
            Spacer(); trailing
        }.padding(.top, 6).padding(.bottom, 8)
    }
}
extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

/// Renders **emphasised** fragments in gold (or white) semibold.
func richText(_ text: String, emphasis: Color = Cosmic.gold) -> Text {
    text.components(separatedBy: "**").enumerated().reduce(Text("")) { acc, p in
        acc + (p.offset % 2 == 1 ? Text(p.element).fontWeight(.semibold).foregroundColor(emphasis) : Text(p.element))
    }
}

struct RichText: View {
    let text: String
    var color = Color(argb: 0xFFE1E3FA), emphasis = Cosmic.gold
    var size: CGFloat = 14
    init(_ text: String, color: Color = Color(argb: 0xFFE1E3FA), emphasis: Color = Cosmic.gold, size: CGFloat = 14) {
        self.text = text; self.color = color; self.emphasis = emphasis; self.size = size
    }
    var body: some View {
        richText(text, emphasis: emphasis).font(.system(size: size)).foregroundStyle(color).lineSpacing(size * 0.45)
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).tracking(0.4).foregroundStyle(Cosmic.muted) }
}

struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(Cosmic.faint).lineSpacing(2) }
}

// MARK: Containers

/// Translucent indigo panel with a soft lavender border.
struct GlassPanel<Content: View>: View {
    var glow: Color?
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: { content })
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(glow != nil
                        ? AnyShapeStyle(LinearGradient(colors: [Color(argb: 0xF0161830), Color(argb: 0xF00A0B1A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Cosmic.panel), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(glow ?? Cosmic.panelBorder))
    }
}

/// A titled panel: section heading above a glass panel.
struct SectionCard<Content: View, Trailing: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { SectionTitle(text: title) { trailing } }
            GlassPanel { content }
            if let footer { Note(footer).padding(.leading, 4).padding(.top, 8) }
        }
    }
}
extension SectionCard where Trailing == EmptyView {
    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, trailing: { EmptyView() }, content: content)
    }
}

// MARK: Buttons & chips

/// Gold-to-amber gradient button with dark text.
struct PrimaryButton: View {
    let text: String
    var icon: String?
    var enabled = true
    var loading = false
    let action: () -> Void
    var body: some View {
        let active = enabled && !loading
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(Cosmic.onGold) }
                else {
                    if let icon { Image(systemName: icon) }
                    Text(text).font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(active ? Cosmic.onGold : Cosmic.muted)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(active ? AnyShapeStyle(Cosmic.goldGradient) : AnyShapeStyle(Color(argb: 0x33F5C66B)), in: RoundedRectangle(cornerRadius: 14))
        }.disabled(!active)
    }
}

/// Translucent outlined button.
struct GhostButton: View {
    let text: String
    var icon: String?
    var color = Cosmic.starText
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(text).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(color).padding(.horizontal, 16).frame(height: 44)
            .background(Color(argb: 0x12FFFFFF), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
        }
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (v, p) in zip(subviews, arrange(subviews, width: bounds.width).points) {
            v.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + rowH))
    }
}

/// Wrapping row of chips. Pass `onRemove` to show a remove "×" on each.
struct ChipFlow: View {
    let items: [String]
    var accent = false
    var onRemove: ((String) -> Void)?
    var body: some View {
        FlowLayout { ForEach(items, id: \.self) { item in Pill(text: item, accent: accent, onRemove: onRemove.map { f in { f(item) } }) } }
    }
}

/// Keyword chip: gold-tinted, or neutral glass.
struct Pill: View {
    let text: String
    var accent = false
    var onRemove: (() -> Void)?
    var emphasised = false
    var body: some View {
        let gold = accent || emphasised
        let fg = gold ? Cosmic.goldSoft : Cosmic.body
        HStack(spacing: 4) {
            Text(text).font(.system(size: emphasised ? 13.5 : 12.5, weight: emphasised ? .semibold : .regular))
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.7).frame(width: 20, height: 20) }
                    .accessibilityLabel("Remove \(text)")
            }
        }
        .foregroundStyle(fg)
        .padding(.leading, 11).padding(.trailing, onRemove != nil ? 4 : 11).padding(.vertical, 5)
        .background(emphasised ? Color(argb: 0x2EF5C66B) : accent ? Color(argb: 0x1AF5C66B) : Color(argb: 0x0FFFFFFF), in: Capsule())
        .overlay(Capsule().stroke(gold ? Color(argb: 0x4DF5C66B) : Color(argb: 0x1AFFFFFF)))
    }
}

/// Labelled percentage bar that fills in when shown.
struct PercentBar: View {
    let label: String, percent: Int
    let color: Color, top: Bool
    @State private var shown = false
    var body: some View {
        HStack {
            Text(label).frame(width: 84, alignment: .leading)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 4).fill(Color(argb: 0x0FFFFFFF))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: g.size.width * (shown ? Double(percent) / 100 : 0))
                    }
            }.frame(height: 8)
            Text("\(percent)%").frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 12.5, weight: top ? .semibold : .regular))
        .foregroundStyle(top ? Cosmic.starText : Cosmic.muted)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = true } }
    }
}

/// List item with a glyph bullet (✦ strengths, ◇ growth edges).
struct GlyphItem: View {
    let glyph: String, text: String
    var glyphColor = Cosmic.gold
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(glyph).font(.system(size: 13)).foregroundStyle(glyphColor).frame(width: 22, alignment: .leading)
            richText(text, emphasis: .white).font(.system(size: 13.5)).foregroundStyle(Color(argb: 0xFFD6D9F2)).lineSpacing(4)
        }.padding(.vertical, 5)
    }
}

/// Tappable row with a leading icon, for settings-style actions.
struct ActionRow: View {
    let icon: String, text: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(destructive ? Cosmic.error : Cosmic.gold)
                Text(text).foregroundStyle(destructive ? Cosmic.error : Cosmic.starText)
                Spacer()
            }.padding(.vertical, 4).contentShape(Rectangle())
        }
    }
}

/// Small numbered circle used in step lists.
struct StepNumber: View {
    let n: Int
    var body: some View {
        Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(Cosmic.gold)
            .frame(width: 24, height: 24).background(Color(argb: 0x2EF5C66B), in: Circle())
    }
}

/// Sign / planet glyphs forced to text (not emoji) presentation.
func glyph(_ symbol: String) -> String { symbol + "\u{FE0E}" }
