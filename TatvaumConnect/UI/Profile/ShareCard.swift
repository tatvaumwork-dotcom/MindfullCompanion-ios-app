import UIKit

/// The shareable "My Cosmic Profile" card (1080×1350, Instagram portrait). The birth chart is drawn
/// as a tilted zodiac ring with each planet at its birth position.
enum ShareCard {
    private static let W: CGFloat = 1080, H: CGFloat = 1350
    private static let gold = rgb(0xFFF5C66B), muted = rgb(0xFF9AA0C8), soft = rgb(0xFFD6D9F2), white = UIColor.white
    private static let VS = "\u{FE0E}"
    private static let signGlyphs = ["♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓"].map { $0 + "\u{FE0E}" }
    private static let planetGlyph: [VedicPlanet: String] = [
        .Sun: "☉", .Moon: "☽", .Mars: "♂", .Mercury: "☿", .Jupiter: "♃", .Venus: "♀", .Saturn: "♄", .Rahu: "☊", .Ketu: "☋",
    ]
    private static let planetColor: [VedicPlanet: UInt32] = [
        .Moon: 0xDFE6F5, .Mercury: 0xB9B2A8, .Venus: 0xF3D9A4, .Sun: 0xFFD36B, .Mars: 0xE0623F,
        .Jupiter: 0xD9B48A, .Saturn: 0xE8D39A, .Rahu: 0xC58CFF, .Ketu: 0x8C6BD6,
    ]

    private static func rgb(_ argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(argb >> 24) / 255)
    }

    static func render(_ c: CosmicProfile, planets: [PlanetPosition], ascendantLongitude: Double, birthMillis: Int64,
                       place: String, now: Int64 = nowMillis()) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format).image { r in
            draw(r.cgContext, c, planets, ascendantLongitude, birthMillis, place, now)
        }
    }

    private static func draw(_ g: CGContext, _ c: CosmicProfile, _ planets: [PlanetPosition], _ asc: Double,
                             _ birthMillis: Int64, _ place: String, _ now: Int64) {
        let s = c.simple
        let space = CGColorSpaceCreateDeviceRGB()

        // background + stars
        let bg = CGGradient(colorsSpace: space, colors: [rgb(0xFF1A1236).cgColor, rgb(0xFF0B0D1F).cgColor, rgb(0xFF071426).cgColor] as CFArray,
                            locations: [0, 0.5, 1])!
        g.drawLinearGradient(bg, start: .zero, end: CGPoint(x: W, y: H), options: [])
        var rnd = SplitMix64(state: UInt64(bitPattern: birthMillis))
        func rf() -> CGFloat { CGFloat(Double(rnd.next() >> 11) / Double(1 << 53)) }
        for _ in 0..<260 {
            g.setFillColor(white.withAlphaComponent(rf() * 0.6 + 0.15).cgColor)
            let x = rf() * W, y = rf() * H, r = rf() * 1.6 + 0.3
            g.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }

        // header
        text("✦  MY COSMIC PROFILE  ✦", W / 2, 74, 30, gold, bold: true)
        if !place.trimmingCharacters(in: .whitespaces).isEmpty { text(place, W / 2, 118, 26, rgb(0xFFB9BDE0)) }

        // birth-chart sky
        let sky = CGRect(x: 48, y: 150, width: W - 96, height: 470)
        let skyPath = UIBezierPath(roundedRect: sky, cornerRadius: 28).cgPath
        g.saveGState()
        g.addPath(skyPath); g.clip()
        g.setFillColor(rgb(0x14FFFFFF).cgColor); g.fill(sky)
        drawChart(g, planets, asc, sky.midX, 330)
        let fade = CGGradient(colorsSpace: space, colors: [rgb(0x000B0D1F).cgColor, rgb(0xF20B0D1F).cgColor] as CFArray, locations: [0, 1])!
        g.drawLinearGradient(fade, start: CGPoint(x: 0, y: sky.minY + sky.height * 0.55), end: CGPoint(x: 0, y: sky.maxY), options: [])
        g.restoreGState()
        g.setStrokeColor(rgb(0x40A0AAFF).cgColor); g.setLineWidth(2); g.addPath(skyPath); g.strokePath()

        // nutshell over the faded bottom of the sky
        text(s.heartLine, W / 2, sky.maxY - 70, 40, white, bold: true)
        text(s.insideLine, W / 2, sky.maxY - 26, 30, soft)

        // three sides
        let cw = (W - 96 - 2 * 24) / 3
        let cy: CGFloat = 660
        for (i, item) in [(s.personality, "MY PERSONALITY"), (s.feelings, "MY FEELINGS"), (s.firstImpression, "FIRST IMPRESSION")].enumerated() {
            let (b, title) = item
            let x = 48 + CGFloat(i) * (cw + 24)
            let r = UIBezierPath(roundedRect: CGRect(x: x, y: cy, width: cw, height: 230), cornerRadius: 22).cgPath
            g.setFillColor(rgb(0x0FFFFFFF).cgColor); g.addPath(r); g.fillPath()
            g.setStrokeColor(rgb(0x38A0AAFF).cgColor); g.setLineWidth(2); g.addPath(r); g.strokePath()
            let cx = x + cw / 2
            text(title, cx, cy + 42, 20, muted, bold: true, maxWidth: cw - 16)
            text(signGlyphs[b.sign.ordinal], cx, cy + 128, 72, rgb(UInt32(CosmicProfile.ELEMENT_COLOR[b.element]!)))
            text(b.sign.label, cx, cy + 176, 32, white, bold: true, maxWidth: cw - 16)
            text(b.subtitle, cx, cy + 210, 24, gold, maxWidth: cw - 16)
        }

        // keyword chips in centred rows
        let chipFont = font(26, bold: true)
        let chips = c.keywords.prefix(6).map { ($0.word, ($0.word as NSString).size(withAttributes: [.font: chipFont]).width + 44) }
        var rows: [[(String, CGFloat)]] = [[]], rowW: [CGFloat] = [0]
        for ch in chips {
            if rowW[rowW.count - 1] + ch.1 > W - 120 { rows.append([]); rowW.append(0) }
            rows[rows.count - 1].append(ch); rowW[rowW.count - 1] += ch.1 + 14
        }
        var y: CGFloat = 930
        for (ri, row) in rows.enumerated() where !row.isEmpty {
            var x = (W - (rowW[ri] - 14)) / 2
            for (w, width) in row {
                let r = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: 52), cornerRadius: 26).cgPath
                g.setFillColor(rgb(0x24F5C66B).cgColor); g.addPath(r); g.fillPath()
                g.setStrokeColor(rgb(0x80F5C66B).cgColor); g.setLineWidth(2); g.addPath(r); g.strokePath()
                text(w, x + width / 2, y + 35, 26, gold, bold: true)
                x += width + 14
            }
            y += 64
        }

        // three stats
        let sy = max(y + 18, 1080)
        for (i, item) in [("DRIVEN BY", s.drives), ("MY STYLE", s.style), ("MY ENERGY", s.energy)].enumerated() {
            let x = 48 + CGFloat(i) * (cw + 24) + cw / 2
            text(item.0, x, sy, 20, muted, bold: true)
            text(item.1.first(where: \.top)?.label ?? "", x, sy + 44, 34, white, bold: true, maxWidth: cw)
        }

        // life chapter + fun fact
        g.setStrokeColor(rgb(0x2EA0AAFF).cgColor); g.setLineWidth(2)
        g.move(to: CGPoint(x: 120, y: sy + 82)); g.addLine(to: CGPoint(x: W - 120, y: sy + 82)); g.strokePath()
        if let moon = planets.first(where: { $0.planet == .Moon }) {
            let chain = DashaToday.chain(birthMillis: birthMillis, moonSiderealLongitude: moon.siderealLongitude, now: now)
            if let md = chain.first?.period {
                let year = Calendar.current.component(.year, from: Date(timeIntervalSince1970: Double(md.endMillis) / 1000))
                let phase = chain.count > 1 ? " · phase: \(chain[1].period.lord.label)" : ""
                text("Life chapter: \(md.lord.label) (\(DashaToday.THEME[md.lord]!.mood)) until \(year)\(phase)", W / 2, sy + 130, 27, soft)
            }
        }
        let days = (now - birthMillis) / 86_400_000
        let laps = Int(Double(now - birthMillis) / (365.256363 * 86_400_000))
        text("\(Int(days).formatted()) days on Earth · \(laps) laps around the Sun", W / 2, sy + 172, 25, muted)
        text("✦ Tatvaum · your mindful cosmic companion", W / 2, H - 34, 22, rgb(0xCCF5C66B), bold: true)
    }

    /// Tilted zodiac ring (ascendant on the left, like a chart) with the planets at their birth longitudes.
    private static func drawChart(_ g: CGContext, _ planets: [PlanetPosition], _ asc: Double, _ cx: CGFloat, _ cy: CGFloat) {
        let rx: CGFloat = 420, ry: CGFloat = 150
        func pt(_ lon: Double, _ k: CGFloat) -> CGPoint {
            let a = (180.0 + (lon - asc)) * .pi / 180
            return CGPoint(x: cx + rx * k * CGFloat(cos(a)), y: cy - ry * k * CGFloat(sin(a)))
        }
        let space = CGColorSpaceCreateDeviceRGB()
        // glow at the centre (Earth)
        g.saveGState()
        g.addEllipse(in: CGRect(x: cx - 240, y: cy - 110, width: 480, height: 220)); g.clip()
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0x55F5C66B).cgColor, rgb(0x00F5C66B).cgColor] as CFArray, locations: [0, 1])!
        g.drawRadialGradient(glow, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: 160, options: [])
        g.restoreGState()
        // ring bands
        g.setStrokeColor(rgb(0x66F5C66B).cgColor); g.setLineWidth(3)
        g.strokeEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        g.setStrokeColor(rgb(0x33A0AAFF).cgColor); g.setLineWidth(2)
        g.strokeEllipse(in: CGRect(x: cx - rx * 0.78, y: cy - ry * 0.78, width: 2 * rx * 0.78, height: 2 * ry * 0.78))
        // sign boundaries + glyphs (sidereal signs start at multiples of 30°)
        for i in 0..<12 {
            let a = pt(Double(i) * 30, 0.78), b = pt(Double(i) * 30, 1)
            g.setStrokeColor(rgb(0x40A0AAFF).cgColor); g.setLineWidth(2)
            g.move(to: a); g.addLine(to: b); g.strokePath()
            let gp = pt(Double(i) * 30 + 15, 1.13)
            text(signGlyphs[i], gp.x, gp.y + 10, 28, rgb(0xB3C9CDF0))
        }
        // Earth
        g.setFillColor(rgb(0xFF4A90D9).cgColor); g.fillEllipse(in: CGRect(x: cx - 14, y: cy - 14, width: 28, height: 28))
        g.setFillColor(rgb(0xFF6FE0A8).cgColor); g.fillEllipse(in: CGRect(x: cx - 10, y: cy - 9, width: 12, height: 12))
        // planets, nearer ones drawn last so they sit in front
        for pl in planets.sorted(by: { pt($0.siderealLongitude, 0.89).y < pt($1.siderealLongitude, 0.89).y }) {
            let p = pt(pl.siderealLongitude, 0.89)
            let col = planetColor[pl.planet] ?? 0xFFFFFF
            let halo = CGGradient(colorsSpace: space, colors: [rgb(0x66000000 | col).cgColor, rgb(col).cgColor.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            g.drawRadialGradient(halo, startCenter: p, startRadius: 0, endCenter: p, endRadius: 30, options: [])
            g.setFillColor(rgb(0xFF000000 | col).cgColor)
            g.fillEllipse(in: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22))
            text((planetGlyph[pl.planet] ?? "") + VS, p.x, p.y - 20, 26, rgb(0xFF000000 | col))
        }
    }

    private static func font(_ size: CGFloat, bold: Bool) -> UIFont { .systemFont(ofSize: size, weight: bold ? .bold : .regular) }

    /// Text centred on `x` with its baseline at `y`, shrunk to fit `maxWidth` when needed.
    private static func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UIColor,
                             bold: Bool = false, maxWidth: CGFloat = W - 120) {
        var f = font(size, bold: bold)
        var w = (s as NSString).size(withAttributes: [.font: f]).width
        if w > maxWidth { f = font(size * maxWidth / w, bold: bold); w = (s as NSString).size(withAttributes: [.font: f]).width }
        (s as NSString).draw(at: CGPoint(x: x - w / 2, y: y - f.ascender), withAttributes: [.font: f, .foregroundColor: color])
    }
}
