import SwiftUI

/// The Tatvaum mark: a calligraphic "t" circled by an orbit and its planet
/// (geometry from the Android app's branding/tatvaum-logo.svg, in its 1254×1254 viewBox).
/// Platform-neutral so Scripts/render-logo.swift can render the app icon and launch image from it.
enum TatvaumLogo {
    static let viewBox: CGFloat = 1254
    static let cream = Color(red: 0xFD / 255, green: 0xF8 / 255, blue: 0xF1 / 255)
    static let space = Color(red: 0x05 / 255, green: 0x06 / 255, blue: 0x0D / 255)

    /// rotate(-13 640 600) from the SVG.
    private static let tilt = CGAffineTransform(translationX: -640, y: -600)
        .concatenating(CGAffineTransform(rotationAngle: -13 * .pi / 180))
        .concatenating(CGAffineTransform(translationX: 640, y: 600))

    /// Outer ellipse minus an offset inner one, so the orbit is thick at left and thin at right. Fill even-odd.
    static let orbit: Path = {
        var p = Path()
        p.addEllipse(in: CGRect(x: 640 - 412, y: 600 - 168, width: 824, height: 336))
        p.addEllipse(in: CGRect(x: 668 - 368, y: 603 - 118, width: 736, height: 236))
        return p.applying(tilt)
    }()

    /// The stretch of orbit hidden where the planet sits in the static mark.
    static let orbitGap: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 889, y: 633)); p.addLine(to: CGPoint(x: 1150, y: 548)); p.addLine(to: CGPoint(x: 1150, y: 800))
        p.closeSubpath()
        return p
    }()

    /// The "t" stem with its angled top.
    static let stem: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 540, y: 322))
        p.addLine(to: CGPoint(x: 643, y: 250))
        p.addLine(to: CGPoint(x: 643, y: 800))
        p.addCurve(to: CGPoint(x: 722, y: 920), control1: CGPoint(x: 643, y: 862), control2: CGPoint(x: 672, y: 912))
        p.addCurve(to: CGPoint(x: 836, y: 890), control1: CGPoint(x: 764, y: 926), control2: CGPoint(x: 806, y: 912))
        p.addCurve(to: CGPoint(x: 846, y: 902), control1: CGPoint(x: 846, y: 884), control2: CGPoint(x: 852, y: 893))
        p.addCurve(to: CGPoint(x: 706, y: 986), control1: CGPoint(x: 818, y: 948), control2: CGPoint(x: 772, y: 986))
        p.addCurve(to: CGPoint(x: 541, y: 800), control1: CGPoint(x: 612, y: 986), control2: CGPoint(x: 541, y: 906))
        p.closeSubpath()
        return p
    }()

    /// Where the planet sits in the static mark.
    static let restingPlanet = CGPoint(x: 889, y: 633)

    // MARK: orbit animation (one lap per `lap` seconds)

    static let lap: Double = 1.4
    /// Start angle on the orbit (lower right, in front of the stem).
    private static let theta0 = atan2((705.6 - 601) / 143, (920.0 - 654) / 390)

    /// Planet centre at `fraction` (0…1) of a lap.
    static func planet(at fraction: Double) -> CGPoint {
        let th = theta0 + fraction * 2 * .pi
        return CGPoint(x: 654 + 390 * cos(th), y: 601 + 143 * sin(th)).applying(tilt)
    }

    /// The planet passes in front of the stem on the near (lower) half of the orbit.
    static func inFront(at fraction: Double) -> Bool {
        let f = fraction - fraction.rounded(.down)
        return f < 0.4038 || f >= 0.9038
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// The mark drawn into any square, in viewBox units scaled to fit.
/// `fraction` nil draws the static mark (planet at rest with the orbit gap); otherwise the planet is mid-orbit.
struct TatvaumMark: View {
    var fraction: Double?
    var ink = TatvaumLogo.cream
    var halo = TatvaumLogo.space

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / TatvaumLogo.viewBox
            ctx.translateBy(x: (size.width - TatvaumLogo.viewBox * k) / 2, y: (size.height - TatvaumLogo.viewBox * k) / 2)
            ctx.scaleBy(x: k, y: k)
            if let fraction {
                let p = TatvaumLogo.planet(at: fraction), front = TatvaumLogo.inFront(at: fraction)
                ctx.fill(TatvaumLogo.orbit, with: .color(ink), style: FillStyle(eoFill: true))
                if !front { planet(ctx, p, halo: 64) }
                ctx.fill(TatvaumLogo.stem, with: .color(ink))
                if front { planet(ctx, p, halo: 64) }
            } else {
                var orbitCtx = ctx
                var keep = Path(CGRect(x: 0, y: 0, width: TatvaumLogo.viewBox, height: TatvaumLogo.viewBox))
                keep.addPath(TatvaumLogo.orbitGap)
                orbitCtx.clip(to: keep, style: FillStyle(eoFill: true))
                orbitCtx.fill(TatvaumLogo.orbit, with: .color(ink), style: FillStyle(eoFill: true))
                ctx.fill(TatvaumLogo.stem, with: .color(ink))
                planet(ctx, TatvaumLogo.restingPlanet, halo: 61)
            }
        }
    }

    private func planet(_ ctx: GraphicsContext, _ c: CGPoint, halo r: CGFloat) {
        ctx.fill(TatvaumLogo.circle(c, r), with: .color(halo))
        ctx.fill(TatvaumLogo.circle(c, 57), with: .color(ink))
    }
}
