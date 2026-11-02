import SwiftUI

struct SourceLinkView: View {
    let title: String
    let destination: URL?
    let furigana: Bool
    let attribution: String

    var body: some View {
        Group {
            if let destination {
                Link(destination: destination) { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title). Search AniList")
                    .help("Search AniList\n\(attribution)")
            } else {
                label.help(attribution)
            }
        }
        .font(.system(size: 10))
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            FuriganaText(title, enabled: furigana)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if destination != nil {
                Image(systemName: "arrow.up.right.square")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }
}
