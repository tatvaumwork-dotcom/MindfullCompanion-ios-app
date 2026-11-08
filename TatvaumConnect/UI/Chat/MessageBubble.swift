import SwiftUI

/// Chat bubble: gold gradient for the user, glass for the companion, amber for local errors.
struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
                                           bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20)
        let fg = isUser ? Cosmic.onGold : Color(argb: 0xFFE1E3FA), accent = isUser ? Cosmic.onGold : Cosmic.gold
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 48) }
            Group {
                if message.content.isEmpty { TypingDots() }
                else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(Self.parseLines(message.content).enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                if line.bullet { Text("✦  ").foregroundStyle(accent) }
                                Self.inlineMarkdown(line.text, accent).foregroundStyle(fg)
                            }
                        }
                    }
                    .font(.system(size: 16)).textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background {
                if isUser { shape.fill(Cosmic.goldGradient) }
                else if message.isError { shape.fill(Cosmic.warning.opacity(0.16)) }
                else { shape.fill(LinearGradient(colors: [Color(argb: 0xE6181A36), Color(argb: 0xE60E1024)], startPoint: .topLeading, endPoint: .bottomTrailing)) }
            }
            .overlay { if !isUser { shape.stroke(Cosmic.panelBorder) } }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    struct Line { let text: String; let bullet: Bool }

    static func parseLines(_ content: String) -> [Line] {
        content.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { line in
            if let m = ["- ", "* ", "• "].first(where: line.hasPrefix) { return Line(text: String(line.dropFirst(m.count)), bullet: true) }
            return Line(text: line, bullet: false)
        }
    }

    /// Renders `**bold**` and `*italic*` / `_italic_`; anything else is plain text.
    static func inlineMarkdown(_ s: String, _ emphasis: Color) -> Text {
        let c = Array(s)
        var out = Text(""), plain = "", i = 0
        func flush() { out = out + Text(plain); plain = "" }
        func find(_ ch: Character, from: Int, double: Bool = false) -> Int? {
            var j = from
            while j < c.count { if c[j] == ch && (!double || (j + 1 < c.count && c[j + 1] == ch)) { return j }; j += 1 }
            return nil
        }
        while i < c.count {
            if c[i] == "*", i + 1 < c.count, c[i + 1] == "*" {
                if let end = find("*", from: i + 2, double: true), end > i + 2 {
                    flush(); out = out + Text(String(c[(i + 2)..<end])).bold().foregroundColor(emphasis); i = end + 2
                } else { plain += "**"; i += 2 }
            } else if (c[i] == "*" || c[i] == "_"), i + 1 < c.count, c[i + 1] != " " {
                if let end = find(c[i], from: i + 1), end > i + 1 {
                    flush(); out = out + Text(String(c[(i + 1)..<end])).italic(); i = end + 1
                } else { plain.append(c[i]); i += 1 }
            } else { plain.append(c[i]); i += 1 }
        }
        flush()
        return out
    }
}

struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Cosmic.muted).frame(width: 8, height: 8).opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }.padding(.vertical, 6).onAppear { on = true }
    }
}
