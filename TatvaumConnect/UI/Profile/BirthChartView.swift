import SwiftUI

/// Full Vedic birth chart: key facts up top, then the complete report.
struct BirthChartView: View {
    let report: String

    private var facts: [(String, String)] {
        let values = Dictionary(report.split(separator: "\n").compactMap { line -> (String, String)? in
            guard let i = line.firstIndex(of: ":"), i != line.startIndex else { return nil }
            return (line[..<i].trimmingCharacters(in: .whitespaces), line[line.index(after: i)...].trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { a, _ in a })
        return [("Ascendant", "Ascendant"), ("Ascendant Lord", "Ascendant lord"), ("Moon Sign", "Moon sign"),
                ("Moon Nakshatra", "Nakshatra"), ("Sun Sign", "Sun sign")]
            .compactMap { k, label in values[k].flatMap { $0.isEmpty ? nil : (label, $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                let facts = facts
                if !facts.isEmpty {
                    SectionCard(title: "At a glance") {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 12) {
                            ForEach(facts, id: \.0) { label, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    FieldLabel(label)
                                    Text(value).font(.headline).foregroundStyle(Cosmic.starText)
                                }
                            }
                        }
                    }
                }
                SectionCard(title: "Full chart", footer: "Vedic (sidereal, Lahiri) chart with whole-sign houses. Swipe sideways to see wide tables.") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(report).font(.system(size: 11, design: .monospaced)).lineSpacing(2).foregroundStyle(Cosmic.starText)
                            .fixedSize().textSelection(.enabled)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .background(CosmicBackground { EmptyView() })
        .navigationTitle("Birth chart").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { ShareLink(item: report, subject: Text("Birth chart")) } }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
