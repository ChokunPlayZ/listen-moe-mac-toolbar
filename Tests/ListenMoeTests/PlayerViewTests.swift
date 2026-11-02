import AppKit
import SwiftUI
import Testing
@testable import ListenMoe

@MainActor
struct PlayerViewTests {
    @Test func fitsMenuBarPopover() {
        let host = NSHostingView(rootView: PlayerView(radio: RadioModel.shared))
        let size = host.fittingSize
        #expect(size.width == 356)
        #expect(size.height > 400)
        #expect(size.height <= 800)
    }
}
