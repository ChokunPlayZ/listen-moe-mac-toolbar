import AppKit
import RadioCore
import SwiftUI

private typealias SettingsState<Value> = SwiftUI.State<Value>

struct DiscordSettingsView: View {
    @ObservedObject var radio: RadioModel
    @SettingsState private var applicationID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Discord Rich Presence").font(.title2.bold())
            Toggle("Share the current song on Discord", isOn: $radio.discordEnabled)
            VStack(alignment: .leading, spacing: 6) {
                Text("Application ID").font(.headline)
                HStack {
                    TextField("Discord application ID", text: $applicationID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(!DiscordRPCProtocol.isValidApplicationID(applicationID.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                Text("Create an application named LISTEN.moe in the Discord Developer Portal, then copy its Application ID here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Discord Developer Portal ↗", destination: URL(string: "https://discord.com/developers/applications")!)
                    .font(.caption)
            }
            Text(radio.discordState.description)
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Text("Requires the Discord desktop app and activity sharing enabled in Discord. Shares song, artist, station, and available artwork while playing. Pausing or quitting clears the activity. No token or client secret is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { applicationID = radio.discordApplicationID }
    }

    private func save() {
        let value = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DiscordRPCProtocol.isValidApplicationID(value) else { return }
        radio.discordApplicationID = value
        applicationID = value
    }
}

@MainActor
final class DiscordSettingsWindow {
    static let shared = DiscordSettingsWindow()
    private var window: NSWindow?

    func show(radio: RadioModel) {
        if window == nil {
            let host = NSHostingController(rootView: DiscordSettingsView(radio: radio))
            let window = NSWindow(contentViewController: host)
            window.title = "Discord Rich Presence"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
