import SwiftUI

/// Visual style per planet: colour, orbit ring (Moon nearest ... Saturn farthest), sphere size.
struct Look {
    let rgb: UInt32, orbit: Double, size: Double
    var color: Color { Color(argb: 0xFF000000 | rgb) }
    func dark(_ f: Double) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255 * (1 - f), green: Double((rgb >> 8) & 0xFF) / 255 * (1 - f),
              blue: Double(rgb & 0xFF) / 255 * (1 - f))
    }
}

let planetLooks: [VedicPlanet: Look] = [
    .Moon: Look(rgb: 0xDFE6F5, orbit: 0.30, size: 0.050), .Mercury: Look(rgb: 0xB9B2A8, orbit: 0.40, size: 0.040),
    .Venus: Look(rgb: 0xF3D9A4, orbit: 0.50, size: 0.050), .Sun: Look(rgb: 0xFFD36B, orbit: 0.60, size: 0.075),
    .Mars: Look(rgb: 0xE0623F, orbit: 0.70, size: 0.045), .Jupiter: Look(rgb: 0xD9B48A, orbit: 0.80, size: 0.065),
    .Saturn: Look(rgb: 0xE8D39A, orbit: 0.90, size: 0.058), .Rahu: Look(rgb: 0xC58CFF, orbit: 1.0, size: 0.040),
    .Ketu: Look(rgb: 0x8C6BD6, orbit: 1.0, size: 0.040),
]

let signGlyphs = ["♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓"].map(glyph)

/// Birth moment in the birth timezone, or nil without complete birth details.
private func birthMoment(_ p: UserProfile) -> (millis: Int64, date: Date, zone: TimeZone, lat: Double, lon: Double)? {
    guard let ds = p.dateOfBirth, let ts = p.timeOfBirth, let lat = p.birthPlaceLatitude, let lon = p.birthPlaceLongitude else { return nil }
    let d = ds.split(separator: "-").compactMap { Int($0) }, t = ts.split(separator: ":").compactMap { Int($0) }
    guard d.count == 3, t.count >= 2 else { return nil }
    let zone = TimeZone(identifier: p.birthTimezone) ?? .current
    var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
    guard let date = cal.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: t.count > 2 ? t[2] : 0)) else { return nil }
    return (Int64((date.timeIntervalSince1970 * 1000).rounded()), date, zone, lat, lon)
}

private func momentText(_ date: Date, _ zone: TimeZone) -> String {
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.timeZone = zone
    return f.string(from: date)
}

/// Birth-sky scene for the full-screen view, or nil without complete birth details.
nonisolated func fullSkyFor(_ p: UserProfile, _ catalog: SkyCatalog) -> (SkyScene, Int, String)? {
    guard let m = birthMoment(p) else { return nil }
    let scene = SkyModel.compute(epochMillis: m.millis, latitude: m.lat, longitude: m.lon, catalog: catalog)
    let asc = PlanetPositionCalculator.calculateAscendant(epochMillis: m.millis, latitude: m.lat, longitude: m.lon).sign
    let title = [p.placeOfBirth.isEmpty ? nil : p.placeOfBirth, momentText(m.date, m.zone)].compactMap { $0 }.joined(separator: " · ")
    return (scene, asc.ordinal, title)
}

private struct BirthSky {
    let planets: [PlanetPosition]
    let ascendant: Double
    let ascSign: ZodiacSign
    let moment: String
}

private func computeSky(_ p: UserProfile) -> BirthSky? {
    guard let m = birthMoment(p) else { return nil }
    let asc = PlanetPositionCalculator.calculateAscendant(epochMillis: m.millis, latitude: m.lat, longitude: m.lon)
    return BirthSky(planets: PlanetPositionCalculator.calculatePlanetPositions(epochMillis: m.millis),
                    ascendant: asc.longitude, ascSign: asc.sign, moment: momentText(m.date, m.zone))
}

private func showsRetro(_ p: PlanetPosition) -> Bool { p.isRetrograde && p.planet != .Rahu && p.planet != .Ketu }

private func degreeLabel(_ p: PlanetPosition) -> String {
    let d = Int(p.degreesInSign), m = Int((p.degreesInSign - Double(d)) * 60)
    return "\(d)°\(String(format: "%02d", m))′ \(p.sign.label)"
}

struct PlanetsView: View {
    let profile: UserProfile
    let openSettings: () -> Void
    let onOpenSky: () -> Void
    @State private var selected: VedicPlanet?

    init(profile: UserProfile, openSettings: @escaping () -> Void, onOpenSky: @escaping () -> Void) {
        self.profile = profile; self.openSettings = openSettings; self.onOpenSky = onOpenSky
    }

    private func toggle(_ p: VedicPlanet) { selected = selected == p ? nil : p }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CosmicTitle(lead: "Celestial", accent: "Birth Chart", size: 20)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(Cosmic.starText) }
            }.padding(.horizontal, 16).padding(.vertical, 12)

            if let sky = computeSky(profile) {
                ScrollView {
                    VStack(spacing: 14) {
                        Text("The sky when you were born · \(sky.moment)")
                            .font(.system(size: 12)).foregroundStyle(Cosmic.muted).frame(maxWidth: .infinity, alignment: .leading)
                        ZStack(alignment: .topTrailing) {
                            OrreryView(sky: sky, selected: selected, onSelect: toggle)
                            Button(action: onOpenSky) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.white)
                                    .frame(width: 40, height: 40).background(Color.white.opacity(0.15), in: Circle())
                            }.padding(10)
                        }
                        .guideTarget(.skyView)
                        PrimaryButton(text: "Open full-screen sky", icon: "sparkles", action: onOpenSky)
                        if let p = sky.planets.first(where: { $0.planet == selected }) {
                            PlanetDetail(p: p, ascSign: sky.ascSign)
                        } else {
                            Text("Drag to rotate · pinch to zoom · tap a planet")
                                .font(.system(size: 12)).foregroundStyle(Cosmic.muted).frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 0) {
                            ascendantRow(sky)
                            ForEach(sky.planets, id: \.planet) { p in
                                Divider().overlay(Cosmic.panelBorder).padding(.horizontal, 16)
                                planetRow(p, sky.ascSign)
                            }
                        }
                        .padding(.vertical, 6).background(Cosmic.panel, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Cosmic.panelBorder))
                    }.padding(.horizontal, 16).padding(.bottom, 24)
                }
            } else {
                Spacer()
                Text("Add your date, time and place of birth to see the sky at the moment you were born.")
                    .multilineTextAlignment(.center).foregroundStyle(Cosmic.muted).padding(32)
                Spacer()
            }
        }
    }

    private func ascendantRow(_ sky: BirthSky) -> some View {
        let (sign, deg) = PlanetPositionCalculator.signFromLongitude(sky.ascendant)
        return HStack(spacing: 12) {
            Circle().fill(Color(argb: 0xFF7FE7FF)).frame(width: 14, height: 14)
            Text("Ascendant").foregroundStyle(Cosmic.starText)
            Spacer()
            Text("\(Int(deg))° \(sign.label)").font(.system(size: 14)).foregroundStyle(Cosmic.muted)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func planetRow(_ p: PlanetPosition, _ asc: ZodiacSign) -> some View {
        let house = HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: asc)
        return Button { toggle(p.planet) } label: {
            HStack(spacing: 12) {
                PlanetDot(look: planetLooks[p.planet]!, size: 14)
                Text(p.planet.label + (showsRetro(p) ? " ℞" : "")).foregroundStyle(Cosmic.starText)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(degreeLabel(p)).font(.system(size: 14)).foregroundStyle(Cosmic.starText)
                    Text("House \(house)").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(p.planet == selected ? Cosmic.gold.opacity(0.15) : .clear)
        }.buttonStyle(.plain)
    }
}

struct PlanetDot: View {
    let look: Look, size: CGFloat
    var body: some View {
        Circle().fill(RadialGradient(colors: [.white, look.color, look.dark(0.5)], center: .center, startRadius: 0, endRadius: size * 0.75))
            .frame(width: size, height: size)
    }
}

private struct PlanetDetail: View {
    let p: PlanetPosition, ascSign: ZodiacSign
    var body: some View {
        let house = HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: ascSign)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlanetDot(look: planetLooks[p.planet]!, size: 14)
                Text(p.planet.label).font(.system(size: 16, weight: .medium)).foregroundStyle(Cosmic.starText)
                Spacer()
                if showsRetro(p) { Text("Retrograde").font(.system(size: 12, weight: .medium)).foregroundStyle(Cosmic.retro) }
            }
            HStack { fact("Sign", degreeLabel(p)); fact("House", "\(house)") }
            HStack { fact("Nakshatra", p.nakshatra.label); fact("Pada", "\(p.pada)") }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: 0xF0161830), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Cosmic.gold.opacity(0.6)))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            FieldLabel(label)
            Text(value).foregroundStyle(Cosmic.starText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: 3D orrery

private final class HitBox { var targets: [(VedicPlanet, CGPoint, Double, Double)] = [] }   // planet, pos, scale, depth

private struct OrreryView: View {
    let sky: BirthSky
    let selected: VedicPlanet?
    let onSelect: (VedicPlanet) -> Void

    @State private var yaw = 0.0
    @State private var pitch = 1.05
    @State private var zoom = 1.0
    @State private var auto = true
    @State private var t0 = Date()
    @State private var lastDrag = CGSize.zero
    @State private var zoomBase = 1.0
    @State private var hits = HitBox()
    private static let stars: [SIMD3<Double>] = (0..<90).map { i in
        var g = SeededRNG(seed: UInt64(i + 1)); return SIMD3(g.next(), g.next(), g.next())
    }
    private static let rings = Array(Set(planetLooks.values.map(\.orbit))).sorted()
    private static let band = Color(argb: 0xFFA5A3FF)

    /// Stop auto-rotation, keeping the current angle.
    private func freeze(_ now: Date) {
        if auto { yaw += now.timeIntervalSince(t0) * 0.12; auto = false }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !auto)) { tl in
            Canvas { ctx, size in draw(ctx, size, yaw: yaw + (auto ? tl.date.timeIntervalSince(t0) * 0.12 : 0)) }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(RadialGradient(colors: [Color(argb: 0xFF1C1B3A), Color(argb: 0xFF0A0A16)], center: .center, startRadius: 0, endRadius: 300))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                Image(systemName: "globe.europe.africa.fill").font(.system(size: 12)).foregroundStyle(Color(argb: 0xFF4FA3FF))
                Text("Earth at centre · sidereal zodiac").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }.padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in
                freeze(Date())
                yaw -= Double(v.translation.width - lastDrag.width) * 0.008
                pitch = min(1.45, max(0.15, pitch - Double(v.translation.height - lastDrag.height) * 0.006))
                lastDrag = v.translation
            }
            .onEnded { _ in lastDrag = .zero }
            .simultaneously(with: MagnifyGesture()
                .onChanged { freeze(Date()); zoom = min(2.2, max(0.7, zoomBase * $0.magnification)) }
                .onEnded { _ in zoomBase = zoom }))
        .onTapGesture { tap in
            freeze(Date())
            hits.targets.filter { hypot(tap.x - $0.1.x, tap.y - $0.1.y) < 28 * max($0.2, 0.8) }
                .max { $0.3 < $1.3 }.map { onSelect($0.0) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, yaw: Double) {
        let cx = size.width / 2, cy = size.height / 2, m = min(size.width, size.height)
        let radius = m * 0.36 * zoom, cp = cos(pitch), sp = sin(pitch)
        func project(_ lon: Double, _ r: Double, _ h: Double = 0) -> (p: CGPoint, s: Double, d: Double) {
            let a = lon * .pi / 180 + yaw
            let x = r * cos(a), y = r * sin(a)
            let yt = y * cp - h * sp, zt = y * sp + h * cp
            let s = 3.2 / (3.2 - zt)
            return (CGPoint(x: cx + x * radius * s, y: cy - yt * radius * s), s, zt)
        }
        func ring(_ r: Double, _ color: Color, dashed: Bool = false, width: Double) {
            var path = Path()
            for deg in stride(from: 0, through: 360, by: 4) {
                let p = project(Double(deg), r).p
                if deg == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dashed ? [8, 8] : []))
        }
        func dot(_ c: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        func label(_ s: String, _ size: Double, _ weight: Font.Weight, _ color: Color, at p: CGPoint, anchor: UnitPoint = .center) {
            ctx.draw(Text(s).font(.system(size: size, weight: weight)).foregroundColor(color), at: p, anchor: anchor)
        }

        for s in Self.stars {
            ctx.fill(dot(CGPoint(x: s.x * size.width, y: s.y * size.height), 0.6 + s.z * 1.1), with: .color(.white.opacity(0.15 + s.z * 0.5)))
        }
        for r in Self.rings { ring(r, .white.opacity(r == 1 ? 0.22 : 0.12), dashed: r == 1, width: 1) }

        let bandR = 1.18, lav = Self.band
        ring(bandR, lav.opacity(0.55), width: 1.5)
        ring(1.08, lav.opacity(0.25), width: 1)
        let chosen = sky.planets.first { $0.planet == selected }
        let chosenColor = chosen.map { planetLooks[$0.planet]!.color }
        if let chosen, let chosenColor {
            let start = Double(chosen.sign.ordinal) * 30
            var seg = Path()
            for (k, d) in stride(from: 0, through: 30, by: 2).enumerated() {
                let o = project(start + Double(d), bandR).p
                if k == 0 { seg.move(to: o) } else { seg.addLine(to: o) }
            }
            for d in stride(from: 30, through: 0, by: -2) { seg.addLine(to: project(start + Double(d), 1.08).p) }
            seg.closeSubpath()
            ctx.fill(seg, with: .color(chosenColor.opacity(0.28)))
            ctx.stroke(seg, with: .color(chosenColor.opacity(0.9)), lineWidth: 1.5)
        }
        for i in 0..<12 {
            var l = Path(); l.move(to: project(Double(i) * 30, 1.08).p); l.addLine(to: project(Double(i) * 30, bandR).p)
            ctx.stroke(l, with: .color(lav.opacity(0.45)), lineWidth: 1)
            let lp = project(Double(i) * 30 + 15, 1.13)
            let isC = chosen?.sign.ordinal == i
            label(signGlyphs[i], (isC ? 19 : 13) * lp.s, isC ? .bold : .regular, isC ? chosenColor! : Color(argb: 0xFFD9D8FF), at: lp.p)
        }

        let cyan = Color(argb: 0xFF7FE7FF)
        let ascOut = project(sky.ascendant, bandR + 0.06)
        var asc = Path(); asc.move(to: project(sky.ascendant, 0.12).p); asc.addLine(to: ascOut.p)
        ctx.stroke(asc, with: .color(cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [10, 8]))
        label("Asc", 11, .semibold, cyan, at: ascOut.p)

        if let chosen, let chosenColor {
            let from = project(0, 0).p, hit = project(chosen.siderealLongitude, bandR)
            var line = Path(); line.move(to: from); line.addLine(to: hit.p)
            ctx.stroke(line, with: .color(chosenColor.opacity(0.18)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            ctx.stroke(line, with: .color(chosenColor.opacity(0.95)), style: StrokeStyle(lineWidth: 1.6, dash: [12, 8]))
            ctx.fill(dot(hit.p, 14), with: .radialGradient(Gradient(colors: [chosenColor.opacity(0.7), .clear]), center: hit.p, startRadius: 0, endRadius: 14))
            ctx.fill(dot(hit.p, 3.5), with: .color(chosenColor))
            let out = project(chosen.siderealLongitude, bandR + 0.13).p
            let d = Int(chosen.degreesInSign), mn = Int((chosen.degreesInSign - Double(d)) * 60)
            let tag = Text("\(signGlyphs[chosen.sign.ordinal]) \(chosen.sign.label) \(d)°\(String(format: "%02d", mn))′")
                .font(.system(size: 11, weight: .bold)).foregroundColor(chosenColor)
            let sz = ctx.resolve(tag).measure(in: size)
            ctx.fill(Path(roundedRect: CGRect(x: out.x - sz.width / 2 - 6, y: out.y - sz.height / 2 - 3, width: sz.width + 12, height: sz.height + 6), cornerRadius: 6),
                     with: .color(Color(argb: 0xE60A0B1A)))
            ctx.draw(tag, at: out, anchor: .center)
        }

        // Earth + planets, back to front.
        var bodies: [(VedicPlanet?, (p: CGPoint, s: Double, d: Double), Color, Color, Double)] = [
            (nil, project(0, 0), Color(argb: 0xFF4FA3FF), Look(rgb: 0x4FA3FF, orbit: 0, size: 0).dark(0.55), 0.07)]
        for p in sky.planets {
            let l = planetLooks[p.planet]!
            bodies.append((p.planet, project(p.siderealLongitude, l.orbit), l.color, l.dark(0.55), l.size))
        }
        bodies.sort { $0.1.d < $1.1.d }
        hits.targets.removeAll(keepingCapacity: true)
        for (planet, pr, color, dark, frac) in bodies {
            let r = m * frac * 0.5 * pr.s * zoom
            let isSel = planet != nil && planet == selected
            if isSel || planet == .Sun {
                ctx.fill(dot(pr.p, r * 3), with: .radialGradient(Gradient(colors: [color.opacity(0.45), .clear]), center: pr.p, startRadius: 0, endRadius: r * 3))
            }
            ctx.fill(dot(pr.p, r), with: .radialGradient(Gradient(colors: [.white.opacity(0.95), color, dark]),
                     center: CGPoint(x: pr.p.x - r * 0.35, y: pr.p.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
            if isSel { ctx.stroke(dot(pr.p, r + 3), with: .color(.white), lineWidth: 1.5) }
            if let planet {
                hits.targets.append((planet, pr.p, pr.s, pr.d))
                label(planet.label, 10.5 * pr.s, .regular, .white.opacity(0.9), at: CGPoint(x: pr.p.x, y: pr.p.y + r + 2), anchor: .top)
            }
        }
    }
}
