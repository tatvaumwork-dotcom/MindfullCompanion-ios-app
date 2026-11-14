import SwiftUI

/// Left pane listing the selected profile's ended chat sessions, newest first.
struct ConversationsDrawer: View {
    let summaries: [ConversationSummary]
    let onClose: () -> Void
    let onOpen: (ConversationSummary) -> Void
    @State private var shown = false
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let width = min(340, g.size.width * 0.85)
            ZStack(alignment: .leading) {
                Color.black.opacity(shown ? 0.55 : 0).ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityAddTraits(.isButton).accessibilityLabel("Close past conversations")
                panel
                    .frame(width: width).frame(maxHeight: .infinity)
                    .background(Cosmic.panelSolid.ignoresSafeArea())
                    .overlay(alignment: .trailing) { Rectangle().fill(Cosmic.panelBorder).frame(width: 1).ignoresSafeArea() }
                    .offset(x: shown ? min(0, drag) : -width - 1)
                    .gesture(DragGesture().updating($drag) { v, s, _ in s = v.translation.width }
                        .onEnded { v in if v.translation.width < -width / 3 { close() } })
            }
        }
        .onAppear { withAnimation(.snappy) { shown = true } }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: onClose)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                CosmicTitle(lead: "Past", accent: "Conversations", size: 20)
                Text(summaries.isEmpty ? "When you end a chat session, it's saved here." : "\(summaries.count) saved")
                    .font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            Divider().overlay(Cosmic.panelBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Divider().overlay(Cosmic.panelBorder).padding(.horizontal, 20) }
                        Button { onOpen(s) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(Date(timeIntervalSince1970: Double(s.date) / 1000).formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Cosmic.starText)
                                    Spacer()
                                    Text("\(s.messageCount) messages").font(.system(size: 12)).foregroundStyle(Cosmic.muted)
                                }
                                Text(s.summary.isEmpty ? "No summary available." : s.summary)
                                    .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Color(argb: 0xFFD0D3EE))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(.vertical, 6)
            }
        }
    }
}
