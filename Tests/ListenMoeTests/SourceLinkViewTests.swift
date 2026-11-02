import AppKit
import RadioCore
import SwiftUI
import Testing
@testable import ListenMoe

@MainActor
struct SourceLinkViewTests {
    @Test
    func entireSourceRowHasAHitTarget() throws {
        let destination = try #require(AniListLink.destination(for: [SongOrigin(name: "進撃の巨人")], track: nil))
        let host = NSHostingView(rootView: SourceLinkView(
            title: "Anime: 進撃の巨人", destination: destination, attribution: "Station tag"
        ).frame(width: 308))
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: host.fittingSize),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        #expect(host.bounds.width == 308)
        #expect(host.bounds.height >= 24)
        // The icon, text, blank row space, and external-link icon all belong to the link.
        for x in [CGFloat(4), 65, 220, 300] {
            #expect(host.hitTest(CGPoint(x: x, y: host.bounds.midY)) != nil)
        }
    }
}
