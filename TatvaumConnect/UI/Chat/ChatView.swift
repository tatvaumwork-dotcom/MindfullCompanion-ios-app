import SwiftUI

struct ChatView: View {
    let chat: ChatSession
    let llm: LLMService
    let name: String
    let openSettings: () -> Void
    let openConversations: () -> Void

    @State private var input = ""
    @State private var confirmEnd = false
    @FocusState private var focused: Bool

    init(chat: ChatSession, llm: LLMService, name: String, openSettings: @escaping () -> Void,
         openConversations: @escaping () -> Void = {}) {
        self.chat = chat; self.llm = llm; self.name = name; self.openSettings = openSettings
        self.openConversations = openConversations
    }

    var body: some View {
        let messages = chat.messages
        CosmicBackground {
            VStack(spacing: 0) {
                topBar(empty: messages.isEmpty)
                if !llm.isAvailable && messages.isEmpty {
                    Text("Chat isn't available in this version of the app.")
                        .font(.system(size: 14)).foregroundStyle(Cosmic.muted).multilineTextAlignment(.center)
                        .padding(32).frame(maxHeight: .infinity)
                } else if messages.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) { ForEach(messages) { MessageBubble(message: $0).id($0.id) } }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: messages.count) { scroll(proxy, messages) }
                        .onChange(of: messages.last?.content.count) { scroll(proxy, messages) }
                    }
                }
                if llm.isAvailable { inputBar }
            }
        }
        .overlay(alignment: .bottom) { toast }
        .task { if llm.isAvailable { await llm.checkAvailability() } }
        .task(id: chat.notice) {
            guard chat.notice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { withAnimation { chat.notice = nil } }
        }
        .alert("End this session?", isPresented: $confirmEnd) {
            Button("End session") { chat.endSession() }
            Button("Keep chatting", role: .cancel) {}
        } message: {
            Text("The conversation will be summarised and saved to your history. Anything new we learn about you is added to your profile.")
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, _ messages: [ChatMessage]) {
        if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func topBar(empty: Bool) -> some View {
        ZStack {
            (Text("✦ ").foregroundColor(Cosmic.gold) + Text("Tatvaum")).font(.system(size: 18, weight: .bold)).tracking(0.5)
                .foregroundStyle(Cosmic.starText)
            HStack(spacing: 4) {
                Button(action: openConversations) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 18)).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .foregroundStyle(Cosmic.muted).accessibilityLabel("Past conversations").guideTarget(.pastChats)
                if llm.isAvailable { statusPill.guideTarget(.aiStatus) }
                Spacer()
                if !empty && !chat.isGenerating {
                    Button("End session") { confirmEnd = true }.font(.system(size: 14, weight: .medium)).foregroundStyle(Cosmic.gold)
                }
                Button(action: openSettings) { Image(systemName: "gearshape.fill").font(.system(size: 18)) }
                    .foregroundStyle(Cosmic.muted).accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 12).frame(height: 52)
    }

    private var statusPill: some View {
        let (color, label): (Color, String) = switch llm.status {
        case .Checking: (Color(argb: 0xFF9E9EAE), "Checking…")
        case .Ready: (Color(argb: 0xFF22A06B), "AI ready")
        case .Busy: (Color(argb: 0xFFF59E0B), "AI busy")
        case .Unavailable: (Color(argb: 0xFFE5484D), "AI unavailable")
        case .Offline: (Color(argb: 0xFF9E9EAE), "Offline")
        }
        return Button { Task { await llm.checkAvailability(force: true) } } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .phaseAnimator(llm.status == .Checking ? [1.0, 0.3] : [1.0]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.7) }
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Cosmic.starText)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(color.opacity(0.12), in: Capsule())
        }.accessibilityHint("Re-check AI availability")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("✦").font(.system(size: 46)).foregroundStyle(Cosmic.gold)
                .phaseAnimator([-6.0, 6.0]) { $0.offset(y: $1) } animation: { _ in .easeInOut(duration: 2.6) }
            ((name.isEmpty ? Text("") : Text("Hi \(name), ")) + Text("what's on your mind?").foregroundColor(Cosmic.gold))
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Cosmic.starText).multilineTextAlignment(.center)
            Text("Your companion knows your chart. Ask anything.").font(.system(size: 13)).foregroundStyle(Cosmic.muted)
            VStack(spacing: 8) {
                ForEach(["✦ I'm feeling stressed today", "☽ Help me reflect on my week", "☉ What should I focus on?"], id: \.self) { s in
                    GhostButton(text: s) { input = String(s.dropFirst(2)); focused = true }
                }
            }.padding(.top, 8)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { focused = false }
    }

    private var inputBar: some View {
        let generating = chat.isGenerating
        let canSend = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generating
        let active = generating || canSend
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $input, axis: .vertical)
                .lineLimit(1...5).focused($focused).disabled(generating).tint(Cosmic.gold)
                .textInputAutocapitalization(.sentences).foregroundStyle(Cosmic.starText)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.white.opacity(generating ? 0.04 : 0.06), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Cosmic.panelBorder))
            Button {
                if generating { chat.stop() } else { chat.send(input); input = "" }
            } label: {
                Image(systemName: generating ? "stop.fill" : "paperplane.fill").font(.system(size: 18))
                    .foregroundStyle(active ? Cosmic.onGold : Cosmic.muted).frame(width: 52, height: 52)
                    .background(active ? AnyShapeStyle(Cosmic.goldGradient) : AnyShapeStyle(Color.white.opacity(0.12)), in: Circle())
            }
            .disabled(!active).accessibilityLabel(generating ? "Stop" : "Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(Color(argb: 0xE60A0B1A))
    }

    @ViewBuilder private var toast: some View {
        if let n = chat.notice {
            Text(n).font(.system(size: 14)).foregroundStyle(Cosmic.starText)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Cosmic.panelSolid, in: Capsule()).overlay(Capsule().stroke(Cosmic.panelBorder))
                .padding(.bottom, 90).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
