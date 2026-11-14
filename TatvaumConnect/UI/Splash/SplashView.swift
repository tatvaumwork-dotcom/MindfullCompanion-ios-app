import SwiftUI

/// Continues the static launch screen (LaunchLogo on LaunchBackground, same size and place):
/// the planet makes one lap round the "t", then the app fades in.
struct SplashView: View {
    /// Point size of the launch image (Assets: LaunchLogo is 200 pt square).
    static let size: CGFloat = 200
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        ZStack {
            TatvaumLogo.space.ignoresSafeArea()
            TimelineView(.animation(paused: reduceMotion)) { tl in
                let f = reduceMotion ? 0 : min(tl.date.timeIntervalSince(start) / TatvaumLogo.lap, 1)
                TatvaumMark(fraction: f).frame(width: Self.size, height: Self.size)
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
        .task {
            start = .now
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : TatvaumLogo.lap))
            onFinish()
        }
    }
}
