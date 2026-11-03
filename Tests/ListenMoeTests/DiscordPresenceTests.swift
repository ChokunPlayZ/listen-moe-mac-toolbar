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

    @Test func settingsWindowIsOnlyCreatedOnDemandAndIsNotRestored() throws {
        let application = NSApplication.shared
        let existingWindows = application.windows
        let settings = DiscordSettingsWindow()
        #expect(application.windows == existingWindows)

        settings.show(radio: RadioModel.shared)
        let window = try #require(application.windows.first {
            $0.title == "Discord Rich Presence" && !existingWindows.contains($0)
        })
        defer { window.close() }
        #expect(window.isVisible)
        #expect(!window.isRestorable)

        window.close()
        #expect(!window.isVisible)
        settings.show(radio: RadioModel.shared)
        #expect(window.isVisible)
    }
}
