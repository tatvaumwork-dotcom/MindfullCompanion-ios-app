import SwiftUI

// Full-screen sky from the birthplace at the moment of birth: stereographic projection, drag with
// momentum, pinch zoom, tap-to-glide. (Android's "Move phone" gyroscope mode is not ported.)

private typealias V3 = SIMD3<Double>   // x = east, y = north, z = up

private func dir(_ az: Double, _ alt: Double) -> V3 {
    let a = az * .pi / 180, h = alt * .pi / 180
    return V3(cos(h) * sin(a), cos(h) * cos(a), sin(h))
}
private func dir(_ p: SkyPoint) -> V3 { dir(p.azimuth, p.altitude) }
private func norm(_ v: V3) -> V3 { v / (v * v).sum().squareRoot() }
private func cross(_ a: V3, _ b: V3) -> V3 { V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
private func dot(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }

private let minFov = 20.0, maxFov = 130.0, minAlt = -60.0, maxAlt = 89.0
private let zodiacColor = Color(argb: 0xFFB4B2FF)
private let cyan = Color(argb: 0xFF7FE7FF)

private func starColor(_ bv: Float) -> Int {   // index into starPalette
    bv < 0 ? 0 : bv < 0.3 ? 1 : bv < 0.6 ? 2 : bv < 0.9 ? 3 : bv < 1.3 ? 4 : 5
}
private let starPalette = [0xFFBFD4FF, 0xFFE3ECFF, 0xFFFFFFFF, 0xFFFFF1D6, 0xFFFFDDB0, 0xFFFFC08A].map { Color(argb: UInt32($0)) }

/// Everything that never changes while the sky is open, precomputed once.
private final class Prepared {
    let sky: SkyScene
    let planetDirs: [V3], starDirs: [V3], eclipticDirs: [V3], boundaryDirs: [V3], midDirs: [V3], ascDir: V3
    /// Catalogue stars brightest first, in struct-of-arrays form (no per-star objects in the draw loop).
    let sDir: [V3], sMag: [Float], sCol: [UInt8], sPhase: [Float]
    let zodiacLines: [[V3]], otherLines: [[V3]]
    let conLabels: [(String, Bool, V3)]

    init(_ sky: SkyScene) {
        self.sky = sky
        planetDirs = sky.planets.map { dir($0.point) }
        starDirs = sky.stars.map { dir($0.point) }
        eclipticDirs = sky.ecliptic.map { dir($0.point) }
        func at(_ lon: Double) -> V3 { dir(sky.ecliptic.first { $0.sidereal == lon }?.point ?? sky.ascendant) }
        boundaryDirs = (0..<12).map { at(Double($0) * 30) }
        midDirs = (0..<12).map { at(Double($0) * 30 + 14) }
        ascDir = dir(sky.ascendant)
        let sorted = sky.catalogStars.sorted { $0.magnitude < $1.magnitude }
        var g = SeededRNG(seed: 7)
        sDir = sorted.map { dir($0.point) }
        sMag = sorted.map(\.magnitude)
        sCol = sorted.map { UInt8(starColor($0.colorIndex)) }
        sPhase = sorted.map { _ in Float(g.next()) }
        zodiacLines = sky.constellations.filter(\.isZodiac).flatMap { $0.lines.map { $0.map(dir) } }
        otherLines = sky.constellations.filter { !$0.isZodiac }.flatMap { $0.lines.map { $0.map(dir) } }
        conLabels = sky.constellations.map { (String($0.name.uppercased().map(String.init).joined(separator: "\u{2009}")), $0.isZodiac, dir($0.label)) }
    }
}

private final class Hits { var items: [(VedicPlanet, CGPoint)] = [] }

struct SkyView: View {
    let scene: SkyScene
    let ascSignIndex: Int
    let title: String
    let onClose: () -> Void

    init(scene: SkyScene, _ ascSignIndex: Int, _ title: String, onClose: @escaping () -> Void) {
        self.scene = scene; self.ascSignIndex = ascSignIndex; self.title = title; self.onClose = onClose
    }

    @State private var prep: Prepared?
    @State private var az = 0.0
    @State private var alt = 20.0
    @State private var fov = 95.0
    @State private var selected: VedicPlanet?
    @State private var showHint = true
    @State private var camTask: Task<Void, Never>?
    @State private var lastLoc: CGPoint?
    @State private var moved = 0.0
    @State private var pinching = false
    @State private var lastMag = 1.0
    @State private var hits = Hits()

    private var home: (Double, Double, Double) { (scene.ascendant.azimuth, 20, 95) }

    private func look(_ dAz: Double, _ dAlt: Double) {
        az = ((az + dAz).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        alt = min(maxAlt, max(minAlt, alt + dAlt))
    }

    private func stopCamera() { camTask?.cancel(); camTask = nil }

    private func glide(az a1: Double, alt h1: Double, fov f1: Double? = nil) {
        stopCamera()
        let a0 = az, h0 = alt, f0 = fov, f1 = f1 ?? fov, start = Date()
        var dAz = (a1 - a0).truncatingRemainder(dividingBy: 360)
        if dAz > 180 { dAz -= 360 }; if dAz < -180 { dAz += 360 }
        camTask = Task { @MainActor in
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / 0.9)
                let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                az = ((a0 + dAz * e).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                alt = h0 + (min(maxAlt, max(minAlt, h1)) - h0) * e
                fov = f0 + (f1 - f0) * e
                if t >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func select(_ p: VedicPlanet) {
        selected = p; showHint = false
        if let sp = scene.planets.first(where: { $0.position.planet == p }) {
            glide(az: sp.point.azimuth, alt: sp.point.altitude - 12, fov: 60)   // aim a little below, above the card
        }
    }

    private func fling(_ v: CGSize, _ width: Double) {
        stopCamera()
        var vAz = -Double(v.width) * fov / width, vAlt = Double(v.height) * fov / width
        camTask = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled && (abs(vAz) > 0.5 || abs(vAlt) > 0.5) {
                try? await Task.sleep(nanoseconds: 16_000_000)
                let now = Date(), dt = now.timeIntervalSince(last); last = now
                look(vAz * dt, vAlt * dt)
                let decay = exp(-dt * 3.2); vAz *= decay; vAlt *= decay
            }
        }
    }

    private func zoomTo(_ f: Double) { glide(az: az, alt: alt, fov: min(maxFov, max(minFov, f))) }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color(argb: 0xFF03040B)
                if let prep {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        Canvas(rendersAsynchronously: false) { ctx, size in
                            let t = tl.date.timeIntervalSinceReferenceDate
                            drawSky(ctx, size, prep, twinkle: (t / 6).truncatingRemainder(dividingBy: 1), pulse: (t / 1.6).truncatingRemainder(dividingBy: 1))
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if lastLoc == nil { stopCamera(); showHint = false; moved = 0; pinching = false }
                            if let l = lastLoc, !pinching {
                                let dx = v.location.x - l.x, dy = v.location.y - l.y
                                moved += hypot(dx, dy)
                                let deg = fov / g.size.width
                                look(-dx * deg, dy * deg)
                            }
                            lastLoc = v.location
                        }
                        .onEnded { v in
                            if moved < 10 && !pinching { tap(v.location) }
                            else if !pinching { fling(v.velocity, g.size.width) }
                            lastLoc = nil
                        }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { m in
                                pinching = true; stopCamera()
                                fov = min(maxFov, max(minFov, fov / (m.magnification / lastMag))); lastMag = m.magnification
                            }
                            .onEnded { _ in lastMag = 1 }))
                }
                controls
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .task {
            az = home.0
            prep = await Task.detached(priority: .userInitiated) { [scene] in Prepared(scene) }.value
            try? await Task.sleep(nanoseconds: 5_000_000_000); showHint = false
        }
        .onDisappear { stopCamera() }
    }

    private func tap(_ p: CGPoint) {
        let best = hits.items.min { hypot(p.x - $0.1.x, p.y - $0.1.y) < hypot(p.x - $1.1.x, p.y - $1.1.y) }
        if let best, hypot(p.x - best.1.x, p.y - best.1.y) < 44 { select(best.0) } else { selected = nil }
    }

    // MARK: controls

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(Color(argb: 0x991B1A33), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15)))
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                circleButton("chevron.left", onClose)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your birth sky").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 8)

            Spacer()
            VStack(spacing: 10) {
                if showHint && selected == nil {
                    Text("Swipe to look around · tap a planet below").font(.system(size: 13)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10).background(Color(argb: 0xCC1B1A33), in: Capsule())
                        .transition(.opacity)
                }
                if let sp = scene.planets.first(where: { $0.position.planet == selected }) {
                    card(sp).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                planetBar
            }.padding(.bottom, 12)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 10) {
                circleButton("plus") { zoomTo(fov / 1.5) }
                circleButton("minus") { zoomTo(fov * 1.5) }
                circleButton("location") { selected = nil; glide(az: home.0, alt: home.1, fov: home.2) }
            }.padding(.trailing, 12)
        }
        .padding(.top, 44).padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.25), value: selected)
        .animation(.easeInOut(duration: 0.25), value: showHint)
    }

    private var planetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scene.planets, id: \.position.planet) { sp in
                    let p = sp.position.planet, active = p == selected
                    Button { select(p) } label: {
                        HStack(spacing: 8) {
                            PlanetDot(look: planetLooks[p]!, size: 14)
                            Text(p.label).font(.system(size: 14, weight: .medium)).foregroundStyle(active ? Color(argb: 0xFF14132B) : .white)
                        }
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(active ? Color.white : Color(argb: 0x991B1A33), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(active ? 0 : 0.15)))
                    }
                }
            }.padding(.horizontal, 16)
        }
    }

    private func card(_ sp: SkyPlanet) -> some View {
        let p = sp.position
        let house = HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: ZodiacSign.of(index: ascSignIndex))
        let sfx = house / 10 == 1 ? "th" : [1: "st", 2: "nd", 3: "rd"][house % 10] ?? "th"
        let compass = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Int(((sp.point.azimuth + 22.5).truncatingRemainder(dividingBy: 360)) / 45)]
        let visible = sp.point.altitude >= 0 ? "Visible in the sky, \(Int(sp.point.altitude))° above the horizon" : "Below the horizon at that moment"
        let retro = p.isRetrograde && p.planet != .Rahu && p.planet != .Ketu ? " It was moving retrograde." : ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PlanetDot(look: planetLooks[p.planet]!, size: 22)
                Text(p.planet.label).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7)).frame(width: 32, height: 32)
                }
            }
            Text("In \(p.sign.label) (\(Int(p.degreesInSign))°) · \(house)\(sfx) house · \(p.nakshatra.label) nakshatra")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
            Text("\(visible), toward the \(compass).\(retro)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: 0xEE15142B), in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
    }

    // MARK: drawing

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ sc: Prepared, twinkle: Double, pulse: Double) {
        var ctx = ctx
        let w = size.width, h = size.height
        let forward = dir(az, alt)
        let right = norm(abs(forward.z) > 0.999 ? V3(1, 0, 0) : cross(forward, V3(0, 0, 1)))
        let up = cross(right, forward)
        let focal = (w / 2) / (2 * tan(fov / 4 * .pi / 180))
        let cx = w / 2, cy = h / 2
        @inline(__always) func project(_ v: V3, _ limit: Double = -0.6) -> CGPoint? {
            let z = dot(v, forward)
            if z < limit { return nil }
            let k = 2 / (1 + z)
            return CGPoint(x: cx + dot(v, right) * k * focal, y: cy - dot(v, up) * k * focal)
        }
        let margin = 60.0
        @inline(__always) func onScreen(_ o: CGPoint) -> Bool { o.x > -margin && o.x < w + margin && o.y > -margin && o.y < h + margin }
        let zoomScale = min(2.6, max(0.8, 90 / fov))
        func circle(_ c: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        func glow(_ c: CGPoint, _ r: Double, _ color: Color, _ a: Double) {
            ctx.fill(circle(c, r), with: .radialGradient(Gradient(colors: [color.opacity(a), .clear]), center: c, startRadius: 0, endRadius: r))
        }
        func text(_ s: String, _ size: Double, _ weight: Font.Weight, _ color: Color, at p: CGPoint, anchor: UnitPoint = .center) {
            ctx.draw(Text(s).font(.system(size: size, weight: weight)).foregroundColor(color), at: p, anchor: anchor)
        }
        /// Breaks the line where a point is behind the camera or the projection jumps.
        func polyline(_ pts: [CGPoint?], _ path: inout Path) {
            var pen = false, last: CGPoint?
            for p in pts {
                guard let p, last == nil || hypot(p.x - last!.x, p.y - last!.y) <= max(w, h) else { pen = false; last = p; continue }
                if pen { path.addLine(to: p) } else { path.move(to: p) }
                pen = true; last = p
            }
        }
        func stroke(_ path: Path, _ color: Color, _ width: Double) {
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }

        // Night sky: deep at the zenith, a soft glow toward the horizon.
        let horizonY = project(dir(az, 0), -0.97)?.y ?? h * 2
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: Color(argb: 0xFF03040B), location: 0), .init(color: Color(argb: 0xFF0B1030), location: 0.55),
                             .init(color: Color(argb: 0xFF1A2152), location: 0.85), .init(color: Color(argb: 0xFF2B3470), location: 1)]),
            startPoint: CGPoint(x: 0, y: horizonY - h * 1.4), endPoint: CGPoint(x: 0, y: horizonY)))

        // Constellation stick figures.
        for (lines, color, width) in [(sc.otherLines, Color(argb: 0xFF9FB4E8).opacity(0.22), 0.9), (sc.zodiacLines, zodiacColor.opacity(0.42), 1.2)] {
            var path = Path()
            for line in lines { polyline(line.map { project($0) }, &path) }
            stroke(path, color, width)
        }
        for (name, zodiac, v) in sc.conLabels where zodiac || fov <= 110 {
            guard let o = project(v), onScreen(o) else { continue }
            if zodiac { text(name, 11, .semibold, Color(argb: 0xFFC9C7FF).opacity(0.8), at: o) }
            else { text(name, 10, .medium, Color(argb: 0xFF9FB4E8).opacity(0.55), at: o) }
        }

        // Real stars; zooming in reveals fainter ones. Bright ones twinkle individually, the faint majority are
        // batched into one path per colour and magnitude band (ponytail: no twinkle on faint stars).
        let faintest = Float(4.6 + (maxFov - fov) / (maxFov - minFov) * 1.4)
        let rScale = min(1.5, zoomScale)
        var bands = [Path](repeating: Path(), count: 6 * 3)
        for i in 0..<sc.sMag.count {
            let mag = sc.sMag[i]
            if mag > faintest { break }
            guard let o = project(sc.sDir[i]), onScreen(o) else { continue }
            let b = Double(min(1, max(0.08, (faintest - mag) / (faintest + 1.5))))
            let r = (0.6 + b * 2.6) * rScale
            if mag < 3.5 {
                let color = starPalette[Int(sc.sCol[i])]
                let tw = 0.85 + 0.15 * sin((twinkle + Double(sc.sPhase[i])) * 2 * .pi)
                if mag < 2 { glow(o, r * 4, color, 0.35 * tw) }
                ctx.fill(circle(o, r), with: .color(color.opacity((0.35 + 0.65 * b) * tw)))
            } else {
                bands[Int(sc.sCol[i]) * 3 + min(2, Int((mag - 3.5) / 1.1))].addEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r))
            }
        }
        for (k, path) in bands.enumerated() where !path.isEmpty {
            ctx.fill(path, with: .color(starPalette[k / 3].opacity([0.6, 0.45, 0.3][k % 3])))
        }

        // Zodiac belt with sign symbols.
        var belt = Path(); polyline(sc.eclipticDirs.map { project($0) }, &belt)
        stroke(belt, zodiacColor.opacity(0.10), 14); stroke(belt, zodiacColor.opacity(0.18), 5); stroke(belt, zodiacColor.opacity(0.55), 1.2)
        for v in sc.boundaryDirs { if let o = project(v), onScreen(o) { ctx.fill(circle(o, 2), with: .color(zodiacColor.opacity(0.6))) } }
        for (i, v) in sc.midDirs.enumerated() {
            guard let o = project(v), onScreen(o) else { continue }
            let rising = i == ascSignIndex, c = CGPoint(x: o.x, y: o.y - 25)
            ctx.fill(circle(c, 15), with: .color(Color(argb: 0xFF1B1A40).opacity(0.7)))
            ctx.stroke(circle(c, 15), with: .color(zodiacColor.opacity(rising ? 0.9 : 0.35)), lineWidth: 1)
            text(signGlyphs[i], 15, .regular, rising ? .white : zodiacColor, at: c)
        }

        // Names of the brightest stars.
        for (i, s) in sc.sky.stars.enumerated() where !(s.magnitude >= 0.9 && fov >= 60) {
            guard let o = project(sc.starDirs[i]), onScreen(o) else { continue }
            if sc.sMag.isEmpty { ctx.fill(circle(o, 2), with: .color(.white)) }
            text(s.name, 10, .regular, .white.opacity(0.5), at: CGPoint(x: o.x + 7, y: o.y), anchor: .leading)
        }

        // Ground with a glowing horizon.
        let horizon = (0...120).map { project(dir(az + 180 + Double($0) * 3, 0), -0.97) }
        drawGround(&ctx, horizon, project(V3(0, 0, -1), -0.97), size)
        var hp = Path(); polyline(horizon, &hp)
        stroke(hp, Color(argb: 0xFF6FE3B0).opacity(0.12), 12); stroke(hp, Color(argb: 0xFF8FD9B0).opacity(0.85), 1.5)
        for (label, a) in [("N", 0), ("NE", 45), ("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)] {
            guard let o = project(dir(Double(a), 0)), onScreen(o) else { continue }
            let p = CGPoint(x: o.x, y: o.y + 8)
            if label == "N" { text(label, 17, .bold, Color(argb: 0xFFFF8A80), at: p, anchor: .top) }
            else if label.count == 1 { text(label, 17, .bold, Color(argb: 0xFFE6F4EA), at: p, anchor: .top) }
            else { text(label, 11, .medium, Color(argb: 0xFFB9D8C2), at: p, anchor: .top) }
        }

        // Rising sign.
        if let o = project(sc.ascDir), onScreen(o) {
            ctx.fill(circle(o, 12), with: .color(cyan.opacity(0.25)))
            ctx.stroke(circle(o, 6), with: .color(cyan), lineWidth: 2)
            text("Rising sign", 12, .semibold, cyan, at: CGPoint(x: o.x + 16, y: o.y), anchor: .leading)
        }

        // Planets: glowing lit spheres; the selected one pulses.
        hits.items.removeAll(keepingCapacity: true)
        for (i, sp) in sc.sky.planets.enumerated() {
            guard let o = project(sc.planetDirs[i]), onScreen(o) else { continue }
            let planet = sp.position.planet, look = planetLooks[planet]!, below = sp.point.altitude < 0
            let r = look.size * 300 * zoomScale / 2
            glow(o, r * (planet == .Sun ? 4.5 : 2.6), look.color, below ? 0.2 : 0.45)
            var sphere = ctx; sphere.opacity = below ? 0.6 : 1
            sphere.fill(circle(o, r), with: .radialGradient(Gradient(colors: [.white, look.color, look.dark(0.6)]),
                        center: CGPoint(x: o.x - r * 0.35, y: o.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
            if planet == selected {
                ctx.stroke(circle(o, r + 5), with: .color(.white.opacity(0.9)), lineWidth: 2)
                ctx.stroke(circle(o, r + 5 + pulse * 22), with: .color(.white.opacity((1 - pulse) * 0.6)), lineWidth: 2)
            }
            text(planet.label, 13, .semibold, .white.opacity(below ? 0.55 : 1), at: CGPoint(x: o.x, y: o.y + r + 6), anchor: .top)
            hits.items.append((planet, o))
        }
    }

    /// Fills the area below the horizon. Under stereographic projection the horizon is a circle (or line).
    private func drawGround(_ ctx: inout GraphicsContext, _ horizon: [CGPoint?], _ nadir: CGPoint?, _ size: CGSize) {
        let pts = horizon.compactMap { $0 }
        guard pts.count >= 3 else { return }
        let ground = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(argb: 0xE00F2A1E), Color(argb: 0xEB06120C)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        var circle = Path(); circle.addLines(pts); circle.closeSubpath()
        if pts.count == horizon.count {
            if let nadir, circle.contains(nadir, eoFill: true) { ctx.fill(circle, with: ground) }   // looking down
            else {                                                                                  // looking up
                var p = Path(CGRect(x: -size.width, y: -size.height, width: 3 * size.width, height: 3 * size.height))
                p.addPath(circle)
                ctx.fill(p, with: ground, style: FillStyle(eoFill: true))
            }
        } else {                                                                                    // horizon partly behind
            var p = Path(); p.addLines(pts)
            let bottom = max(size.height, pts.map(\.y).max()!) + size.height * 2
            p.addLine(to: CGPoint(x: pts.last!.x, y: bottom)); p.addLine(to: CGPoint(x: pts[0].x, y: bottom)); p.closeSubpath()
            ctx.fill(p, with: ground)
        }
    }
}
