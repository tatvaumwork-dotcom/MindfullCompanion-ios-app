import SwiftUI
import Observation

/// Whether the first-run tour has been seen. Cleared by "Replay the app guide" in Settings.
enum GuidePrefs {
    private static let key = "guide_tour_done_v1"
    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Controls the tour can point at.
enum GuideID: String {
    case tabBar, aiStatus, pastChats, skyView, thisWeek, profileViews, share, settings
}

/// Where each highlighted control currently sits on screen (global coordinates).
@MainActor @Observable
final class GuideTargets {
    var rects: [GuideID: CGRect] = [:]
}

private struct GuideTargetsKey: EnvironmentKey {
    static let defaultValue: GuideTargets? = nil
}

extension EnvironmentValues {
    var guideTargets: GuideTargets? {
        get { self[GuideTargetsKey.self] }
        set { self[GuideTargetsKey.self] = newValue }
    }
}

private struct GuideTargetModifier: ViewModifier {
    let id: GuideID
    @Environment(\.guideTargets) private var targets
    func body(content: Content) -> some View {
        if let targets {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { targets.rects[id] = $0 }
                .onDisappear { targets.rects[id] = nil }
        } else {
            content
        }
    }
}

extension View {
    /// Marks a control the tour can point at. Does nothing outside the main tabs.
    func guideTarget(_ id: GuideID) -> some View { modifier(GuideTargetModifier(id: id)) }
}

private struct GuideStep {
    /// Tab to show behind the step, or nil to stay on the current one.
    let tab: Int?
    let target: GuideID?
    let title: String
    let body: String
}

private let steps: [GuideStep] = [
    GuideStep(tab: nil, target: nil, title: "Welcome to Tatvaum", body: "Here's a quick look at what's where. It takes about 30 seconds, and you can skip any time."),
    GuideStep(tab: 0, target: .tabBar, title: "Chat", body: "Talk to your companion about anything on your mind. It knows the sky you were born under and today's sky, so replies are about you."),
    GuideStep(tab: 0, target: .pastChats, title: "Past conversations", body: "Tap here to open your earlier conversations. When you end a chat, it's saved in this list."),
    GuideStep(tab: 0, target: .aiStatus, title: "Companion status", body: "Green means your companion is ready. If it says busy or offline, tap it to check again."),
    GuideStep(tab: 1, target: .tabBar, title: "Planets", body: "The real sky at the moment you were born, calculated from your birth time and place, with Earth at the centre."),
    GuideStep(tab: 1, target: .skyView, title: "Your birth sky", body: "Drag to rotate, pinch to zoom, and tap any planet to see where it was and what it means for you."),
    GuideStep(tab: 2, target: .tabBar, title: "3rd Eye", body: "A new reflective question arrives every Monday. Sit with it during the week."),
    GuideStep(tab: 2, target: .thisWeek, title: "This week's question", body: "Write whatever comes up and save it. Your past weeks stay below, so you can look back on them."),
    GuideStep(tab: 3, target: .tabBar, title: "Profile", body: "Your cosmic profile: your nature, strengths, the life cycle you're in now, and what you've shared with your companion."),
    GuideStep(tab: 3, target: .profileViews, title: "Change the view", body: "Overall is your whole picture; As of today is what today's sky means for you. Simple and Detailed change how deep it goes."),
    GuideStep(tab: 3, target: .share, title: "Share", body: "Turn your profile into a card to share with friends."),
    GuideStep(tab: 3, target: .settings, title: "Settings", body: "Switch or add profiles, update your birth details, read how the AI works, or replay this guide."),
]

/// Full-screen coach marks: dims the app, cuts a spotlight around one control at a time, and
/// switches tabs so the screen behind matches the step. Steps whose control isn't on screen are skipped.
struct GuideOverlay: View {
    let targets: GuideTargets
    let onShowTab: (Int) -> Void
    let onFinish: () -> Void

    @State private var index = 0
    @State private var forward = true
    /// Steps skipped because their control isn't on screen; kept out of the "x of y" count.
    @State private var skipped: Set<Int> = []

    private var last: Int { steps.count - 1 }

    private func go(_ to: Int) {
        if to > last { onFinish() }
        else if to < 0 { index = 0 }
        else { forward = to >= index; withAnimation(.easeInOut(duration: 0.35)) { index = to } }
    }

    var body: some View {
        let step = steps[index]
        GeometryReader { geo in
            // Full-screen space, so global frames line up with what's drawn.
            let screen = geo.frame(in: .global)
            let target = step.target.flatMap { targets.rects[$0] }
                .map { $0.intersection(screen.insetBy(dx: 0, dy: 4)).offsetBy(dx: -screen.minX, dy: -screen.minY) }
                .flatMap { $0.isNull || $0.height < 20 ? nil : $0 }
            let hole = target?.insetBy(dx: -6, dy: -6)
            let waiting = step.target != nil && target == nil
            ZStack {
                Canvas { ctx, size in
                    var dim = Path(CGRect(origin: .zero, size: size))
                    if let hole {
                        let r = min(16, hole.height / 2)
                        dim.addPath(Path(roundedRect: hole, cornerRadius: r))
                        ctx.fill(dim, with: .color(Color(argb: 0xE003040B)), style: FillStyle(eoFill: true))
                        ctx.stroke(Path(roundedRect: hole, cornerRadius: r), with: .color(Cosmic.gold), lineWidth: 2)
                    } else {
                        ctx.fill(dim, with: .color(Color(argb: 0xE003040B)))
                    }
                }
                // Swallow every touch so the app underneath can't be used mid-tour.
                .contentShape(Rectangle())
                .onTapGesture {}

                if !waiting {
                    let card = GuideCard(
                        title: step.title, text: step.body,
                        position: index + 1 - skipped.filter { $0 < index }.count,
                        count: steps.count - skipped.count,
                        isLast: index == last,
                        onSkip: onFinish,
                        onBack: index > 0 ? { go(index - 1) } : nil,
                        onNext: { go(index + 1) })
                        .frame(maxWidth: 520).padding(.horizontal, 20)
                    if let hole {
                        if hole.midY < geo.size.height / 2 {
                            VStack { card.padding(.top, max(hole.maxY + 14, geo.safeAreaInsets.top)); Spacer(minLength: 0) }
                        } else {
                            VStack { Spacer(minLength: 0); card.padding(.bottom, geo.size.height - hole.minY + 14) }
                        }
                    } else {
                        card
                    }
                }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .task(id: index) {
            if let tab = step.tab { onShowTab(tab) }
            // Give a newly shown tab time to lay out; if the control still isn't there, move past the step.
            guard let id = step.target else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, targets.rects[id] == nil else { return }
            skipped.insert(index)
            go(forward ? index + 1 : index - 1)
        }
    }
}

private struct GuideCard: View {
    let title: String, text: String
    let position: Int, count: Int
    let isLast: Bool
    let onSkip: () -> Void
    let onBack: (() -> Void)?
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(position) of \(count)").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Cosmic.gold)
            Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(Cosmic.starText)
            Text(text).font(.system(size: 14)).lineSpacing(4).foregroundStyle(Cosmic.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                if !isLast { Button("Skip", action: onSkip).foregroundStyle(Cosmic.muted) }
                Spacer()
                if let onBack { Button("Back", action: onBack).foregroundStyle(Cosmic.starText).padding(.trailing, 8) }
                Button(action: onNext) {
                    Text(isLast ? "Start exploring" : "Next").font(.system(size: 15, weight: .bold)).foregroundStyle(Cosmic.onGold)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Cosmic.gold, in: Capsule())
                }
            }
            .font(.system(size: 15, weight: .medium)).padding(.top, 6)
        }
        .padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cosmic.panelSolid, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Cosmic.gold.opacity(0.45)))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}
