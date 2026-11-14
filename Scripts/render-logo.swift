// Renders the app icon and launch-screen logo from TatvaumConnect/UI/Splash/TatvaumLogo.swift.
// Run from the repo root:  Scripts/render-logo.sh
import AppKit
import SwiftUI

@MainActor
func save<V: View>(_ view: V, size: CGFloat, to path: String, opaque: Bool) {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    renderer.isOpaque = opaque
    guard let cg = renderer.cgImage else { fatalError("render failed: \(path)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

MainActor.assumeIsolated {
    let assets = CommandLine.arguments[1]

    // App icon: the static mark on black, cropped to the SVG's rounded tile (58…1196); iOS rounds the corners.
    let icon: CGFloat = 1024
    let markSize = TatvaumLogo.viewBox * icon / 1138
    save(ZStack { Color.black; TatvaumMark(fraction: nil, halo: .black).frame(width: markSize, height: markSize) }
            .frame(width: icon, height: icon).clipped(),
         size: icon, to: "\(assets)/AppIcon.appiconset/AppIcon.png", opaque: true)

    // Launch logo: the first frame of the splash orbit, transparent, 200 pt at 1x/2x/3x.
    for scale in [1, 2, 3] {
        let px = CGFloat(200 * scale)
        let suffix = scale == 1 ? "" : "@\(scale)x"
        save(TatvaumMark(fraction: 0), size: px, to: "\(assets)/LaunchLogo.imageset/LaunchLogo\(suffix).png", opaque: false)
    }
}
