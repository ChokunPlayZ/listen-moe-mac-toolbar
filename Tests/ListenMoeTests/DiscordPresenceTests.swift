import SwiftUI
import Testing
@testable import ListenMoe

@MainActor
struct DiscordPresenceTests {
    @Test func requiresExplicitConfiguration() {
        let presence = DiscordPresence()
        #expect(presence.state == .disabled)
        presence.configure(enabled: true, applicationID: "")
        #expect(presence.state == .needsApplicationID)
        presence.configure(enabled: false, applicationID: "")
        #expect(presence.state == .disabled)
        presence.shutdown()
    }

    @Test func settingsHaveFixedWidth() {
        let host = NSHostingView(rootView: DiscordSettingsView(radio: RadioModel.shared))
        #expect(host.fittingSize.width == 440)
        #expect(host.fittingSize.height < 600)
    }
}
