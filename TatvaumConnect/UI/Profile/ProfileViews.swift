import SwiftUI

enum ProfileMode: String, CaseIterable { case simple = "Simple", detailed = "Detailed" }
enum ProfileTab: String, CaseIterable { case overall = "Overall", today = "As of today" }

/// Small two-option pill switch.
struct PillSwitch<T: Hashable>: View {
    let options: [T]
    let selected: T
    let label: (T) -> String
    let onSelect: (T) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                let on = o == selected
                Button { withAnimation(.snappy) { onSelect(o) } } label: {
                    Text(label(o)).font(.system(size: 12.5, weight: on ? .bold : .medium))
                        .foregroundStyle(on ? Cosmic.onGold : Cosmic.muted)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(on ? Cosmic.gold : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(argb: 0x0FFFFFFF), in: Capsule())
        .overlay(Capsule().stroke(Cosmic.panelBorder))
    }
}

/// Gold-outlined "Share" pill look.
struct SharePillLabel: View {
    var busy = false
    var body: some View {
        HStack(spacing: 5) {
            if busy { ProgressView().controlSize(.mini).tint(Cosmic.gold) }
            else { Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold)) }
            Text("Share").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Cosmic.gold)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(argb: 0x1FF5C66B), in: Capsule())
        .overlay(Capsule().stroke(Color(argb: 0x73F5C66B)))
    }
}

// MARK: - Overall · Simple

struct SimpleProfilePanel: View {
    let c: CosmicProfile
    let birthMillis: Int64?

    var body: some View {
        let s = c.simple
        GlassPanel {
            SectionTitle("You in a nutshell")
            RichText(s.summary)
            SectionTitle("Your three sides")
            HStack(spacing: 8) {
                ForEach([s.personality, s.feelings, s.firstImpression], id: \.title) { SignCard(b: $0) }
            }
            SectionTitle("What drives you")
            BarList(bars: s.drives)
            RichText(s.drivesText, color: Color(argb: 0xFFD0D3EE), size: 13)
            SectionTitle("How you get things done")
            BarList(bars: s.style)
            RichText(s.styleText, color: Color(argb: 0xFFD0D3EE), size: 13)
            SectionTitle("Your energy")
            BarList(bars: s.energy)
            RichText(s.energyText, color: Color(argb: 0xFFD0D3EE), size: 13)
            SectionTitle("Words that describe you")
            FlowLayout { ForEach(c.keywords, id: \.word) { Pill(text: $0.word, accent: true, emphasised: $0.emphasised) } }
            SectionTitle("Watch out for")
            VStack(spacing: 0) {
                ForEach(Array(s.watchOut.enumerated()), id: \.offset) { i, x in
                    if i > 0 { Divider().overlay(Color(argb: 0x0AFFFFFF)) }
                    GlyphItem(glyph: "◇", text: x, glyphColor: Color(argb: 0xFFC9CDF0))
                }
            }
            SectionTitle("Your life lesson")
            RichText(s.lifeLesson, color: Color(argb: 0xFFD0D3EE), size: 13)
            if let birthMillis { CosmicOdometer(birthMillis: birthMillis) }
            Note("For fun and self-reflection, based on where the planets were when you were born. Switch to Detailed for the full astrology behind it.")
                .padding(.top, 6)
        }
    }
}

struct SignCard: View {
    let b: CosmicProfile.BigThree
    var body: some View {
        VStack(spacing: 2) {
            Text(b.title.uppercased()).font(.system(size: 10.5)).tracking(1).foregroundStyle(Cosmic.muted).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text(signGlyphs[b.sign.ordinal]).font(.system(size: 26)).foregroundStyle(Color(argb: UInt32(CosmicProfile.ELEMENT_COLOR[b.element]!)))
            Text(b.sign.label).font(.system(size: 15, weight: .bold)).foregroundStyle(Cosmic.starText)
            Text(b.subtitle).font(.system(size: 12)).foregroundStyle(Cosmic.muted).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 10).frame(maxWidth: .infinity).frame(height: 132)
        .background(Color(argb: 0x0AFFFFFF), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Cosmic.panelBorder))
    }
}

struct BarList: View {
    let bars: [CosmicProfile.Bar]
    var body: some View {
        VStack(spacing: 7) { ForEach(bars, id: \.label) { PercentBar(label: $0.label, percent: $0.percent, color: Color(argb: UInt32($0.color)), top: $0.top) } }
    }
}

struct ProgressLine: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            Capsule().fill(Color(argb: 0x14FFFFFF))
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: g.size.width * min(max(fraction, 0), 1)) }
        }.frame(height: 5)
    }
}

/// How many times each body has gone round its orbit since birth, plus a few big-picture facts.
private struct CosmicOdometer: View {
    let birthMillis: Int64
    var body: some View {
        let days = Double(nowMillis() - birthMillis) / 86_400_000
        if days > 0 {
            SectionTitle("Since you were born · cosmic odometer")
            RichText("You have been alive for **\(Int(days).formatted())** days. Here's how many times each one has gone round its orbit since then:",
                     color: Color(argb: 0xFFD0D3EE), size: 13)
            VStack(spacing: 10) { ForEach(DashaToday.ODOMETER, id: \.name) { row($0, days) } }
            let yrs = days / 365.25
            VStack(spacing: 0) {
                GlyphItem(glyph: "✦", text: "The Sun has passed through each of the 12 constellations, Aries to Pisces, **\(Int(days / 365.256363))** times, one full lap of the zodiac every year.")
                GlyphItem(glyph: "✦", text: "The constellations themselves are slowly turning too: precession has slid the zodiac **\(String(format: "%.1f", yrs * 50.29 / 60))′**, which is **\(String(format: "%.3f", yrs / 25772 * 100))%** of its 25,772-year cycle. That's why the ayanamsa keeps growing.")
                GlyphItem(glyph: "✦", text: "Riding on Earth, you've travelled **\(big(yrs * 940e6)) km** around the Sun, and the Sun has carried you **\(String(format: "%.2g", yrs / 230e6 * 100))%** of one orbit round the Milky Way.")
            }
        }
    }

    private func big(_ n: Double) -> String { n >= 1e9 ? String(format: "%.2f billion", n / 1e9) : String(format: "%.0f million", n / 1e6) }

    private func fmtN(_ n: Double) -> String {
        n >= 100 ? Int(n.rounded(.down)).formatted() : n >= 10 ? String(format: "%.1f", n) : String(format: "%.2f", n)
    }

    private func row(_ o: DashaToday.Orbiter, _ days: Double) -> some View {
        let orbits = days / o.periodDays
        let done = Int(orbits.rounded(.down))
        let frac = orbits - Double(done)
        let nextIn = (1 - frac) * o.periodDays
        let next = nextIn < 60 ? "\(Int(nextIn.rounded(.up))) days" : nextIn < 730 ? String(format: "%.0f months", nextIn / 30.44) : String(format: "%.1f yrs", nextIn / 365.25)
        let status = done > 0 ? "\(done.formatted()) complete · next in \(next)" : "\(Int(frac * 100))% of its first lap · completes in \(next)"
        let color = Color(argb: o.color)
        return HStack(alignment: .center, spacing: 0) {
            Text(glyph(o.glyph)).font(.system(size: 17)).foregroundStyle(color).frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(o.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Cosmic.starText)
                Text(o.label).font(.system(size: 11)).foregroundStyle(Cosmic.muted)
                Text(status).font(.system(size: 11)).foregroundStyle(Cosmic.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtN(orbits)).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Cosmic.starText)
                ProgressLine(fraction: frac, color: color)
            }.frame(width: 84)
        }
    }
}

// MARK: - As of today

private func day(_ ms: Int64) -> String {
    Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.day().month(.abbreviated).year())
}
private func dayTime(_ ms: Int64) -> String {
    Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.day().month(.abbreviated).hour().minute())
}
private func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

private struct LordTag: View {
    let p: VedicPlanet
    var size: CGFloat = 14
    var body: some View {
        Text("\(p.symbol) \(p.label)").font(.system(size: size, weight: .semibold)).foregroundStyle(planetLooks[p]!.color)
    }
}

struct TodayPanel: View {
    let simple: Bool
    let birthMillis: Int64
    let planets: [PlanetPosition]
    let ascSign: ZodiacSign
    var now = nowMillis()

    private func t(_ p: VedicPlanet) -> DashaToday.Theme { DashaToday.THEME[p]! }

    var body: some View {
        let moonLon = planets.first { $0.planet == .Moon }!.siderealLongitude
        let chain = DashaToday.chain(birthMillis: birthMillis, moonSiderealLongitude: moonLon, now: now)
        GlassPanel {
            if chain.isEmpty {
                Text("The Vimshottari cycle (120 years) has completed for this birth date.").font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            } else {
                content(chain)
            }
        }
    }

    @ViewBuilder private func content(_ chain: [DashaToday.Running]) -> some View {
        let md = chain[0].period
        let ad = chain.count > 1 ? chain[1].period : nil
        SectionTitle("As of today · \(dayTime(now))")
        if let ad {
            if simple {
                RichText("You are in your **\(md.lord.label)** life chapter, \(t(md.lord).meaning). It runs until **\(day(md.endMillis))**. " +
                         (md.lord == ad.lord
                          ? "You are also in its own **\(ad.lord.label)** phase, so this energy is at full strength until \(day(ad.endMillis))."
                          : "Inside that, the current **\(ad.lord.label)** phase (until \(day(ad.endMillis))) adds a mood of **\(t(ad.lord).mood)**: \(t(ad.lord).meaning)."))
            } else {
                let names = chain.enumerated().map { i, r in
                    "**\(r.period.lord.label)** " + (i < 3 ? DashaToday.LEVELS[i].name : String(DashaToday.LEVELS[i].name.split(separator: " ")[0]))
                }
                let rel = DashaToday.relationText(DashaToday.relation(md.lord, ad.lord))
                RichText("Running " + names.joined(separator: " / ") + ". " +
                         (md.lord == ad.lord ? "The Mahadasha lord is running its own sub-period, which \(rel)." : "\(md.lord.label) and \(ad.lord.label) \(rel)."))
            }
        }

        // One row per level: name, lord, mood, progress, dates, time left.
        VStack(spacing: 12) {
            ForEach(Array(chain.enumerated()), id: \.offset) { i, r in levelRow(i, r.period) }
        }

        if let ad {
            if simple {
                SectionTitle("Good time for")
                VStack(spacing: 0) { ForEach(unique([t(md.lord).goodFor, t(ad.lord).goodFor]), id: \.self) { GlyphItem(glyph: "✦", text: cap($0)) } }
                SectionTitle("Go easy on")
                VStack(spacing: 0) { ForEach(unique([t(md.lord).goEasy, t(ad.lord).goEasy]), id: \.self) { GlyphItem(glyph: "◇", text: cap($0), glyphColor: Color(argb: 0xFFC9CDF0)) } }
                if chain.count > 2 {
                    let pd = chain[2].period
                    let sd = chain.count > 3 ? chain[3].period : nil, prd = chain.count > 4 ? chain[4].period : nil
                    RichText("Shorter cycles: these few weeks lean toward **\(t(pd.lord).mood)**" +
                             (sd.map { ", these days toward **\(t($0.lord).mood)**" } ?? "") +
                             (prd.map { ", and this very hour toward **\(t($0.lord).mood)**" } ?? "") + ".",
                             color: Color(argb: 0xFFD0D3EE), size: 13)
                }
            } else {
                SectionTitle("Dasha lords in your chart")
                VStack(spacing: 0) {
                    ForEach(Array(chain.prefix(3).enumerated()), id: \.offset) { i, r in
                        GlyphItem(glyph: "\(i + 1)", text: lordLine(i, r.period.lord))
                    }
                }
                SectionTitle("\(md.lord.label) Mahadasha · antardashas")
                PeriodTable(periods: chain[1].siblings, current: ad, now: now)
                SectionTitle("Mahadasha timeline")
                PeriodTable(periods: chain[0].siblings, current: md, now: now, showYears: true)
                let moonNak = CosmicProfile.NAK_NAMES[planets.first { $0.planet == .Moon }!.nakshatra.ordinal]
                Note("Vimshottari dasha from the natal Moon in \(moonNak) (Lahiri ayanamsa). Years of 365.25 days. Sukshma and Prana periods are very sensitive to birth time: one minute of birth time shifts them noticeably.")
            }
        }
    }

    private func unique(_ xs: [String]) -> [String] { xs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

    private func lordLine(_ i: Int, _ lord: VedicPlanet) -> String {
        let n = DashaToday.natalLord(lord, planets: planets, ascSign: ascSign)
        let rules = n.rules.isEmpty ? "" :
            ", ruling house\(n.rules.count > 1 ? "s" : "") **\(n.rules.map(String.init).joined(separator: " & "))** (\(n.rules.map { DashaToday.HOUSE_TITLES[$0 - 1] }.joined(separator: "; ")))"
        return "**\(DashaToday.LEVELS[i].name) · \(lord.label)**: natally in \(n.sign.label) in house **\(n.house)** (\(DashaToday.HOUSE_TITLES[n.house - 1])), " +
            "\(n.nakshatra) nakshatra\(rules)\(n.dignity.map { "; \($0.lowercased())" } ?? "")\(n.retrograde ? "; retrograde" : ""). Brings \(t(lord).meaning)."
    }

    private func levelRow(_ i: Int, _ p: Vimshottari.Period) -> some View {
        let lvl = DashaToday.LEVELS[i]
        let done = Double(now - p.startMillis) / Double(p.endMillis - p.startMillis)
        let fmt = i >= 3 ? dayTime : day
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(simple ? lvl.simple : lvl.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Cosmic.starText)
                Text(simple ? lvl.span : lvl.simple).font(.system(size: 10.5)).foregroundStyle(Cosmic.muted)
            }.frame(width: 118, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    LordTag(p: p.lord)
                    Text("  \(t(p.lord).mood)").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                }
                ProgressLine(fraction: done, color: planetLooks[p.lord]!.color)
                Text("\(fmt(p.startMillis)) → \(fmt(p.endMillis)) · \(DashaToday.timeLeft(p.endMillis - now)) left")
                    .font(.system(size: 11)).foregroundStyle(Cosmic.muted)
            }
        }
    }
}

private struct PeriodTable: View {
    let periods: [Vimshottari.Period]
    let current: Vimshottari.Period
    let now: Int64
    var showYears = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(periods, id: \.startMillis) { p in
                let on = p.startMillis == current.startMillis
                let dateColor = p.endMillis < now ? Cosmic.muted.opacity(0.6) : Cosmic.muted
                HStack(spacing: 4) {
                    LordTag(p: p.lord, size: 13).frame(maxWidth: .infinity, alignment: .leading)
                    Text(day(p.startMillis)).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(dateColor)
                    Text(day(p.endMillis)).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(dateColor)
                    if showYears {
                        Text("\(Int(Vimshottari.ORDER.first { $0.planet == p.lord }!.years)) yrs").font(.system(size: 11))
                            .foregroundStyle(Cosmic.muted).frame(width: 44, alignment: .trailing)
                    }
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(on ? Color(argb: 0x1FF5C66B) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
