import SwiftUI

extension VedicPlanet {
    var symbol: String {
        let s: String = switch self {
        case .Sun: "☉"; case .Moon: "☽"; case .Mars: "♂"; case .Mercury: "☿"; case .Jupiter: "♃"
        case .Venus: "♀"; case .Saturn: "♄"; case .Rahu: "☊"; case .Ketu: "☋"
        }
        return glyph(s)
    }
    var tint: Color {
        switch self {
        case .Sun: Cosmic.gold; case .Moon: Cosmic.starText; case .Mars: Cosmic.fire; case .Mercury: Cosmic.earth
        case .Jupiter: Cosmic.air; case .Venus: Color(argb: 0xFFFF9AD5); case .Saturn: Cosmic.lavender
        case .Rahu: Color(argb: 0xFFC58CFF); case .Ketu: Color(argb: 0xFF8C6BD6)
        }
    }
}

func monthLabel(_ ms: Int64) -> String { Vimshottari.date(millis: ms).formatted(.dateTime.month(.abbreviated).year()) }
func dayLabel(_ ms: Int64) -> String { Vimshottari.date(millis: ms).formatted(.dateTime.day().month(.abbreviated).year()) }

private struct PlanetGlyph: View {
    let planet: VedicPlanet
    var size: CGFloat = 18
    var body: some View {
        Text(planet.symbol).font(.system(size: size)).foregroundStyle(planet.tint).frame(width: size + 8, alignment: .leading)
    }
}

/// "Vimshottari Dasha": what's running now, plus the full timeline with sub-periods.
struct DashaPanel: View {
    let timeline: [Vimshottari.Period]
    var now = nowMillis()
    var body: some View {
        let current = Vimshottari.current(timeline: timeline, at: now)
        GlassPanel {
            SectionTitle("Vimshottari Dasha")
            if let current {
                Text("RUNNING NOW").font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(Cosmic.gold)
                VStack(spacing: 8) {
                    PeriodLine(label: "Mahadasha", p: current.maha)
                    PeriodLine(label: "Antardasha", p: current.antar)
                    PeriodLine(label: "Pratyantar", p: current.pratyantar)
                }
                let m = current.maha
                let progress = min(1, max(0, Double(now - m.startMillis) / Double(m.endMillis - m.startMillis)))
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 4).fill(Color(argb: 0x0FFFFFFF))
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 4).fill(Cosmic.goldGradient).frame(width: g.size.width * progress) }
                }.frame(height: 8)
                Text("\(Int(progress * 100))% through your \(m.lord.label) mahadasha").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
            }
            SectionTitle("Timeline")
            VStack(spacing: 0) { ForEach(timeline, id: \.startMillis) { MahaRow(maha: $0, now: now) } }
            Note("The first period began before birth; only its remaining balance counts from your birth date. Tap a period to see its sub-periods.")
        }
    }
}

private struct PeriodLine: View {
    let label: String
    let p: Vimshottari.Period
    var body: some View {
        HStack {
            PlanetGlyph(planet: p.lord, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.lord.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Cosmic.starText)
                Text(label.uppercased()).font(.system(size: 10)).tracking(1).foregroundStyle(Cosmic.muted)
            }
            Spacer()
            Text("\(dayLabel(p.startMillis)) – \(dayLabel(p.endMillis))").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
        }
    }
}

private struct MahaRow: View {
    let maha: Vimshottari.Period
    let now: Int64
    @State private var expanded: Bool
    init(maha: Vimshottari.Period, now: Int64) {
        self.maha = maha; self.now = now
        _expanded = State(initialValue: maha.contains(t: now))
    }
    var body: some View {
        let isNow = maha.contains(t: now), past = maha.endMillis <= now
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PlanetGlyph(planet: maha.lord)
                Text(maha.lord.label + (isNow ? "  · now" : "")).font(.system(size: 14, weight: isNow ? .bold : .medium))
                    .foregroundStyle(isNow ? Cosmic.gold : past ? Cosmic.muted : Cosmic.starText)
                Spacer()
                Text("\(monthLabel(maha.startMillis)) – \(monthLabel(maha.endMillis))").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Cosmic.muted)
            }
            if expanded {
                VStack(spacing: 4) {
                    ForEach(maha.sub, id: \.startMillis) { a in
                        let aNow = a.contains(t: now)
                        HStack {
                            PlanetGlyph(planet: a.lord, size: 13)
                            Text(a.lord.label).font(.system(size: 13, weight: aNow ? .bold : .regular))
                                .foregroundStyle(aNow ? Cosmic.gold : a.endMillis <= now ? Cosmic.muted : Color(argb: 0xFFD0D3EE))
                            Spacer()
                            Text("\(monthLabel(a.startMillis)) – \(monthLabel(a.endMillis))").font(.system(size: 11.5)).foregroundStyle(Cosmic.muted)
                        }
                    }
                }.padding(.leading, 26)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isNow ? Color(argb: 0x14F5C66B) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay { if isNow { RoundedRectangle(cornerRadius: 10).stroke(Cosmic.gold.opacity(0.5)) } }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }
}
