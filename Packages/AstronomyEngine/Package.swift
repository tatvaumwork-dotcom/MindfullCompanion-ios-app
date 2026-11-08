// swift-tools-version:5.9
import PackageDescription

// Astronomy Engine v2.1.19 (MIT) — the same engine the Android app uses.
let package = Package(
    name: "AstronomyEngine",
    products: [.library(name: "CAstronomy", targets: ["CAstronomy"])],
    targets: [.target(name: "CAstronomy", path: "Sources/CAstronomy", publicHeadersPath: "include")]
)
