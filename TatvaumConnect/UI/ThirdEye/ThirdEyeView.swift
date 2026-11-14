import SwiftUI

struct ThirdEyeView: View {
    let store: ThirdEyeStore
    let openSettings: () -> Void
    @State private var current: ThirdEyeEntry?

    init(store: ThirdEyeStore, openSettings: @escaping () -> Void) { self.store = store; self.openSettings = openSettings }

    var body: some View {
        let cur = current ?? store.current()
        let past = store.entries.filter { $0.weekStart != cur.weekStart }
        ScrollView {
            LazyVStack(spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        CosmicTitle(lead: "Your Third", accent: "Eye")
                        Subtitle("A question for your inner eye every Monday morning. Sit with it all week.")
                    }
                    Spacer()
                    Button(action: openSettings) { Image(systemName: "gearshape.fill").foregroundStyle(Cosmic.muted).frame(width: 44, height: 44) }
                        .accessibilityLabel("Settings")
                }
                NudgeCard(store: store)
                ThisWeek(entry: cur, store: store).id(cur.weekStart).guideTarget(.thisWeek)
                if !past.isEmpty {
                    SectionTitle("Past weeks").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(past, id: \.weekStart) { PastQuestion(entry: $0) }
                }
                Note("Tip: add the Third Eye widget to your home screen from the widget gallery.")
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CosmicBackground { EmptyView() })
        .onAppear { current = store.current() }
    }
}

private func weekLabel(_ iso: String) -> String {
    ThirdEye.date(fromKey: iso)?.formatted(.dateTime.month(.abbreviated).day()) ?? iso
}

/// Asks for notification permission so the Monday question can arrive as a notification.
private struct NudgeCard: View {
    let store: ThirdEyeStore
    @State private var enabled = true
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if !enabled {
                GlassPanel(padding: 16) {
                    HStack(spacing: 10) {
                        Text("🔔").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get a Monday nudge").font(.system(size: 15, weight: .semibold)).foregroundStyle(Cosmic.starText)
                            Text("We'll notify you when your new Third Eye question arrives.").font(.system(size: 12.5)).foregroundStyle(Cosmic.muted)
                        }
                    }
                    GhostButton(text: "Enable notifications", color: Cosmic.gold) {
                        Task {
                            if await ThirdEyeNotifier.enable(store: store) { enabled = true }
                            else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                }
            }
        }
        .task(id: phase) { enabled = await ThirdEyeNotifier.canNotify() }
    }
}

private struct ThisWeek: View {
    let entry: ThirdEyeEntry
    let store: ThirdEyeStore
    @State private var answer: String
    @State private var saved: Bool
    @FocusState private var focused: Bool

    init(entry: ThirdEyeEntry, store: ThirdEyeStore) {
        self.entry = entry; self.store = store
        _answer = State(initialValue: entry.answer)
        _saved = State(initialValue: !entry.answer.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        GlassPanel(glow: Cosmic.gold.opacity(0.7)) {
            HStack {
                Text("THIS WEEK · \(weekLabel(entry.weekStart))".uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(Cosmic.gold)
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { tl in
                    Text(nextLabel(tl.date)).font(.system(size: 11)).foregroundStyle(Cosmic.muted)
                }
            }
            ThirdEyeGlyph().frame(width: 120, height: 64).frame(maxWidth: .infinity).padding(.vertical, 6)
            Text(entry.question).font(.system(size: 21, weight: .bold)).lineSpacing(6).foregroundStyle(Cosmic.starText)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            TextField("Write what comes up…", text: $answer, axis: .vertical)
                .lineLimit(3...8).focused($focused).tint(Cosmic.gold).padding(14).foregroundStyle(Cosmic.starText)
                .background(Color(argb: 0x0AFFFFFF), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? Cosmic.gold : Cosmic.panelBorder))
                .onChange(of: answer) { saved = false }
            PrimaryButton(text: saved ? "Reflection saved ✦" : "Save reflection",
                          enabled: !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saved) {
                store.saveAnswer(weekStart: entry.weekStart, answer: answer)
                saved = true; focused = false
            }
        }
    }

    private func nextLabel(_ now: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: ThirdEye.nextArrival(now: now))
        let d = c.day ?? 0, h = c.hour ?? 0
        return d >= 1 ? "next in \(d)d \(h)h" : h >= 1 ? "next in \(h)h" : "next in \(max(1, c.minute ?? 0))m"
    }
}

private struct PastQuestion: View {
    let entry: ThirdEyeEntry
    @State private var expanded = false
    var body: some View {
        GlassPanel(padding: 16) {
            Text("👁  Week of \(weekLabel(entry.weekStart))".uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Cosmic.muted)
            Text(entry.question).font(.system(size: 15, weight: .semibold)).lineSpacing(4).foregroundStyle(Cosmic.starText)
            if entry.answer.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No reflection written").font(.system(size: 12.5).italic()).foregroundStyle(Cosmic.muted)
            } else {
                Text(expanded ? entry.answer : "✦ " + entry.answer).font(.system(size: 13.5)).lineSpacing(3)
                    .foregroundStyle(Color(argb: 0xFFD0D3EE)).lineLimit(expanded ? nil : 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }
}

/// A softly glowing, blinking "third eye".
private struct ThirdEyeGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let glow = 0.35 + 0.45 * (0.5 - 0.5 * cos(t / 1.8 * .pi))
            let blink = t.truncatingRemainder(dividingBy: 4.2) / 4.2
            let open = blink > 0.93 ? min(1, max(0.08, 1 - sin((blink - 0.93) / 0.07 * .pi))) : 1.0
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let ink = Color(argb: 0xFF14152E)
                let gr = size.width * 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: 2 * gr, height: 2 * gr)),
                         with: .radialGradient(Gradient(colors: [Cosmic.gold.opacity(glow * 0.55), .clear]), center: c, startRadius: 0, endRadius: gr))
                let eyeH = size.height * 0.62 * open, hw = size.width * 0.42
                var eye = Path()
                eye.move(to: CGPoint(x: c.x - hw, y: c.y))
                eye.addQuadCurve(to: CGPoint(x: c.x + hw, y: c.y), control: CGPoint(x: c.x, y: c.y - 2 * eyeH))
                eye.addQuadCurve(to: CGPoint(x: c.x - hw, y: c.y), control: CGPoint(x: c.x, y: c.y + 2 * eyeH))
                ctx.fill(eye, with: .color(ink))
                ctx.stroke(eye, with: .color(Cosmic.gold), lineWidth: 2)
                if open > 0.3 {
                    func dot(_ r: Double, _ at: CGPoint, _ s: GraphicsContext.Shading) {
                        ctx.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)), with: s)
                    }
                    dot(size.height * 0.2 * open, c, .radialGradient(Gradient(colors: [Color(argb: 0xFFFFE6A8), Cosmic.gold, Cosmic.amber]), center: c, startRadius: 0, endRadius: size.height * 0.24))
                    dot(size.height * 0.08 * open, c, .color(ink))
                    dot(size.height * 0.035, CGPoint(x: c.x - size.height * 0.06, y: c.y - size.height * 0.06), .color(.white.opacity(0.8)))
                }
                ctx.stroke(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(Cosmic.gold.opacity(0.25)), lineWidth: 1)
            }
        }
    }
}
