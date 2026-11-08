import SwiftUI

struct SessionDetailView: View {
    let summary: ConversationSummary
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(summary.messages) { m in
                    let user = m.role == .user
                    Text(m.content).font(.system(size: 15)).foregroundStyle(user ? Cosmic.onGold : Cosmic.starText).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(user ? AnyShapeStyle(Cosmic.goldGradient) : AnyShapeStyle(Cosmic.panel), in: RoundedRectangle(cornerRadius: 18))
                        .overlay { if !user { RoundedRectangle(cornerRadius: 18).stroke(Cosmic.panelBorder) } }
                        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
                        .padding(user ? .leading : .trailing, 40)
                }
            }.padding(16)
        }
        .background(CosmicBackground { EmptyView() })
        .navigationTitle(Date(timeIntervalSince1970: Double(summary.date) / 1000).formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Text("\(summary.messageCount) messages").font(.caption).foregroundStyle(Cosmic.muted) } }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
